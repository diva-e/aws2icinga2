require 'aws-sdk'
require 'json'
require_relative '../icinga/host.rb'

module Service
  # get all hosts
  def self.hosts
    config_services = Config.services
    hosts = []

    [
      self::ElasticLoadBalancing,
      self::ElasticLoadBalancingV2,
      self::EC2,
      self::AutoScaling,
      self::ElastiCache,
      self::Redshift,
      self::RDS,
      self::BatchJobQueue,
      self::DatabaseMigrationService,
      self::VPN
    ].each do |service|
      if config_services.include? service.type
        config_services.delete service.type
        hosts += service.hosts
      end
    end
    raise 'Unknown services configured: ' + config_services.inspect unless config_services.empty?
    hosts
  end

  # add generic methods, attributes
  module Generic
    attr_accessor :type, :client

    # should this resource be ignored?
    def ignore_tags(tags)
      tags.each do |tag|
        if @type == 'ec2' && Config.ec2_ignore_autoscaling
          return true if tag.key == 'aws:autoscaling:groupName'
        end
        return true if Config.ignore_tags[tag.key] == tag.value
      end
      false
    end

    def struct_hash(struct)
      struct.map do |var|
        attrs = {}
        var.each_pair { |key, val| attrs[key.to_s] = val }
        attrs
      end
    end

    # to differ between account, prefix names/id with package name
    def prefix_unique(value)
      "aws-#{@type}-#{Config.package_name}-#{ENV['AWS_REGION']}-#{value}"
    end

    # like prefix_unique, bot for display name
    def display_name(value)
      "AWS #{@type} - #{Config.package_name} #{ENV['AWS_REGION']} - #{value}"
    end
  end

  module EC2
    extend Generic

    @client = Aws::EC2::Client.new
    @type = 'ec2'

    # Get all ec2 hosts
    def self.hosts
      hosts = []
      # @todo implement tag filter here
      #
      # filtering by tag keys "key1" or "key2"
      # ec2.describe_instances(filters:[{ name: 'tag-key', values: ['key1', 'key2'] }])

      # filtering by tag values "value1" or "value1"
      # ec2.describe_instances(filters:[{ name: 'tag-value', values: ['value1', 'value2'] }])

      # filtering by key and value, key equals "key1" and value equals "value1" or "value2"
      # ec2.describe_instances(filters:[{ name: "tag:key1", values: ['value1'] }])
      response = @client.describe_instances
      response.reservations.each do |res|
        res.instances.each do |inst|
          next if ignore_tags(inst[:tags])
          next if inst[:state].name == 'terminated'
          vars = Dictionary.new(@type, inst[:instance_id])
          vars.ip(inst[:public_ip_address], inst[:private_ip_address])
          vars.dns(inst[:public_dns_name], inst[:private_dns_name])

          vars.availability_zones = inst[:placement][:availability_zone]
          vars.instance_type = inst[:instance_type]

          # prefer private ip
          hostname = inst[:private_dns_name] || inst[:public_dns_name]
          address = inst[:private_ip_address] || inst[:public_ip_address]

          vars.tags(inst[:tags])
          icinga = Icinga2Host.new(hostname, address)

          icinga.display_name = if Config.ec2_tag_name && vars.vars['tags'][Config.ec2_tag_name]
                                  "AWS #{@type} - #{vars.vars['tags'][Config.ec2_tag_name]} - #{inst[:instance_id]} (#{address})"
                                else
                                  "AWS #{@type} - #{inst[:instance_id]} (#{address})"
                                end

          disks = []
          inst[:block_device_mappings].each do |d|
            disks.push d[:device_name]
          end

          vars.add('ec2',
                   'launch_time' => inst[:launch_time].to_i, # Time to unix timestamp
                   'block_devices' => disks)

          icinga.vars = {
            'aws' => vars.to_hash,
            # AWS does only send Windows, so assume its linux by default
            'os' => inst[:platform] ? inst[:platform] : 'Linux'
          }
          hosts.push icinga
        end
      end
      hosts
    end
  end

  # Part of EC2 api
  module VPN
    extend Generic

    @client = Aws::EC2::Client.new
    @type = 'vpn'

    # Get all hosts
    def self.hosts
      hosts = []
      response = @client.describe_vpn_connections
      response.vpn_connections.each do |inst|
        next if ignore_tags(inst[:tags])
        next unless %w(pending available).include?(inst[:state])

        vars = Dictionary.new(@type, inst[:vpn_connection_id])
        vars.tags(inst[:tags])
        vars.add('vpn', 'type' => inst[:type],
                        'gateways' => inst[:vgw_telemetry].map { |e| e[:outside_ip_address] },
                        'customer_gateway_id' => inst[:customer_gateway_id],
                        'vpn_gateway_id' => inst[:vpn_gateway_id])

        icinga = Icinga2Host.new(prefix_unique(inst[:vpn_connection_id]), 'localhost')
        # no real host to check, only service or sub nodes(cluster)
        icinga.check_command = 'dummy'
        icinga.display_name = display_name(inst[:vpn_connection_id])
        icinga.vars = {
          'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  # Layer 4 LB aka classic
  module ElasticLoadBalancing
    extend Generic

    @client = Aws::ElasticLoadBalancing::Client.new
    @type = 'elb'
    # Get all hosts
    def self.hosts
      hosts = []
      response = @client.describe_load_balancers
      response.load_balancer_descriptions.each do |inst|
        vars = Dictionary.new(@type, inst[:load_balancer_name])

        resp = @client.describe_tags(load_balancer_names: [inst[:load_balancer_name]])
        next if ignore_tags(resp.tag_descriptions[0][:tags])
        vars.tags(resp.tag_descriptions[0][:tags])

        vars.dns(inst[:dns_name], nil)
        vars.availability_zones = inst[:availability_zones]
        hostname = inst[:dns_name]
        address = inst[:dns_name]

        # sort by procotol for icinga assignment
        # @todo use vars health check and make icinga applicable for assignment Dictionary
        listens = {}
        inst.listener_descriptions.each do |listen|
          listens[listen[:listener][:protocol]] = {} unless listens[listen[:listener][:protocol]]
          # convert port to string, icinga2 converts it to an floating or similar, which breaks the comparision of the hashes
          listens[listen[:listener][:protocol]][listen[:listener][:load_balancer_port].to_s] = {
            'ssl_certificate_id' => listen[:listener][:ssl_certificate_id]
          }
        end
        vars.add('elb',
                 'scheme' => inst[:scheme],
                 'listener' => listens)

        icinga = Icinga2Host.new(hostname, address)
        icinga.display_name = "AWS #{@type} - #{hostname}"
        icinga.vars = {
          'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  # Layer 7 LB - Application Load Balancer
  module ElasticLoadBalancingV2
    extend Generic

    @client = Aws::ElasticLoadBalancingV2::Client.new
    @type = 'alb'
    @type_targetgroup = 'alb-targetgroup'
    # fetch tags for all loadbalancers in a batch
    def self.tags(lb_arns)
      raise 'Argument needs to be an Array of ARNs' unless lb_arns.is_a?(Array)
      lb_tags = {}
      resp = @client.describe_tags(resource_arns: lb_arns)
      resp.tag_descriptions.each do |tag|
        lb_tags[tag[:resource_arn]] = tag[:tags]
      end
      lb_tags
    end

    # Get all hosts
    def self.hosts
      hosts = []
      loadbalancers = @client.describe_load_balancers.load_balancers

      # prefetch additional attributes in a batch
      lb_arns = []
      loadbalancers.each do |inst|
        lb_arns.push(inst[:load_balancer_arn])
      end
      lb_tags = tags(lb_arns)

      # fetch all target_groups
      lb_targets = {}

      targetgroups = @client.describe_target_groups.target_groups
      # prefetch all tags
      lb_targets_tags = tags(targetgroups.map { |target| target[:target_group_arn] })

      # Add targetgroup if its part of an loadbalancer
      targetgroups.each do |inst|
        inst.load_balancer_arns.each do |lb|
          lb_targets[lb] = {} unless lb_targets[lb]
          # requres an hash for icingas "apply for" rule
          lb_targets[lb][inst[:target_group_name]] = {
            'arn' => inst[:target_group_arn]
          }
        end

        # add Targetgroup as host if lb is active
        next if inst.load_balancer_arns.empty?

        vars = Dictionary.new(@type_targetgroup, inst[:target_group_name])
        vars.arn = inst[:target_group_arn]

        next if ignore_tags(lb_targets_tags[inst[:target_group_arn]])
        vars.tags(lb_targets_tags[inst[:target_group_arn]])

        vars.add(@type_targetgroup, 'healthy_threshold_count' => inst[:healthy_threshold_count],
                                    'unhealthy_threshold_count' => inst[:unhealthy_threshold_count],
                                    'port' => inst[:port],
                                    'protocol' => inst[:protocol],
                                    'load_balancer_arns' => inst[:load_balancer_arns])

        # no real host to check
        icinga = Icinga2Host.new(prefix_unique(inst[:target_group_name]), 'localhost')
        icinga.check_command = 'dummy'

        icinga.display_name = "AWS #{@type_targetgroup} - #{inst[:target_group_name]}"
        icinga.vars = {
          'aws' => vars.to_hash
        }
        hosts.push icinga
      end

      loadbalancers.each do |inst|
        vars = Dictionary.new(@type, inst[:load_balancer_name])
        vars.arn = inst[:load_balancer_arn]

        next if ignore_tags(lb_tags[inst[:load_balancer_arn]])
        vars.tags(lb_tags[inst[:load_balancer_arn]])

        vars.dns(inst[:dns_name], nil)
        vars.availability_zones = inst[:availability_zones].map { |e| e[:zone_name] }
        hostname = inst[:dns_name]
        address = inst[:dns_name]

        # sort by procotol for icinga assignment
        listens = {}
        @client.describe_listeners(load_balancer_arn: inst[:load_balancer_arn]).listeners.each do |listen|
          listens[listen[:protocol]] = {} unless listens[listen[:protocol]]
          # convert port to string, icinga2 converts it to an floating or similar, which breaks the comparision of the hashes
          listens[listen[:protocol]][listen[:port].to_s] = {
            'arn' => listen[:listener_arn],
            'certificates' => struct_hash(listen[:certificates]),
            'ssl_policy' => listen[:ssl_policy]
          }
        end

        target_groups = []
        target_groups = lb_targets[inst[:load_balancer_arn]] if lb_targets[inst[:load_balancer_arn]]
        vars.add('alb',
                 'scheme' => inst[:scheme],
                 'listener' => listens,
                 'target_groups' => target_groups)

        icinga = Icinga2Host.new(hostname, address)
        icinga.display_name = "AWS #{@type} - #{hostname}"
        icinga.vars = {
          'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  module AutoScaling
    extend Generic

    @client = Aws::AutoScaling::Client.new
    @type = 'autoscaling'
    # Get all hosts
    def self.hosts
      hosts = []
      response = @client.describe_auto_scaling_groups
      response.auto_scaling_groups.each do |inst|
        vars = Dictionary.new(@type, inst[:auto_scaling_group_name])
        vars.availability_zones = inst[:availability_zones]
        vars.arn = inst[:auto_scaling_group_arn]
        vars.add('autoscaling', 'desired_capacity' => inst[:desired_capacity],
                                'max_size'  => inst[:max_size],
                                'min_size'  => inst[:min_size],
                                'default_cooldown' =>  inst[:default_cooldown],
                                'health_check_type' => inst[:health_check_type],
                                'load_balancer_names' => inst[:load_balancer_names],
                                'target_group_arns' => inst[:target_group_arns])

        # no real host to check, only service or sub nodes(cluster)
        icinga = Icinga2Host.new(prefix_unique(inst[:auto_scaling_group_name]), 'localhost')
        icinga.check_command = 'dummy'

        icinga.display_name = "AWS #{@type} - #{inst[:auto_scaling_group_name]}"
        icinga.vars = {
          'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  module ElastiCache
    extend Generic

    @client = Aws::ElastiCache::Client.new
    @type = 'elasticache'
    # Get all hosts
    def self.hosts
      hosts = []
      response = @client.describe_cache_clusters(show_cache_node_info: true)
      response.cache_clusters.each do |inst|
        vars = Dictionary.new(@type, inst[:cache_cluster_id])
        # elasticache seems to have tags only for costs
        # resp = @client.list_tags_for_resource(resource_name: inst[:cache_cluster_id])
        # vars.tags(resp.tag_list)

        vars.availability_zones = inst[:preferred_availability_zone]
        vars.instance_type = inst[:cache_node_type]

        if inst[:configuration_endpoint]
          port = inst[:configuration_endpoint][:port]
          address = inst[:configuration_endpoint][:address]
        else
          port = inst[:cache_nodes][0].endpoint[:port]
          address = inst[:cache_nodes][0].endpoint[:address]
        end
        vars.dns(address, nil)

        vars.add('elasticache', 'engine_version' => inst[:engine_version],
                                'engine' => inst[:engine],
                                'num_node' => inst[:num_cache_nodes],
                                'port' => port)

        icinga = Icinga2Host.new(address, address)
        # no real host to check, only service or sub nodes(cluster)
        icinga.check_command = 'dummy'
        icinga.display_name = "AWS #{@type} - #{address}"
        icinga.vars = {
          'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  module Redshift
    extend Generic

    @client = Aws::Redshift::Client.new
    @type = 'redshift'
    # Get all hosts
    def self.hosts
      hosts = []
      response = @client.describe_clusters
      response[:clusters].each do |inst|
        vars = Dictionary.new(@type, inst[:cluster_identifier])
        vars.availability_zones = inst[:availability_zone]
        vars.instance_type = inst[:node_type]
        port = inst[:endpoint][:port]
        address = inst[:endpoint][:address]

        vars.dns(address, nil)

        cluster_nodes = []
        inst[:cluster_nodes].each do |cn|
          cluster_nodes.push({'node_role' => cn[:node_role], 'public_ip_address' => cn[:public_ip_address],
                              'private_ip_address' => cn[:private_ip_address]})
        end

        vars.add(
            @type,
            'cluster_status' => inst[:cluster_status],
            'master_username' => inst[:master_username],
            'db_name' => inst[:db_name],
            'port' => port,
            'cluster_create_time' => inst[:cluster_create_time],
            'preferred_maintenance_window' => inst[:preferred_maintenance_window],
            'cluster_version' => inst[:cluster_version],
            'allow_version_upgrade' => inst[:allow_version_upgrade],
            'cluster_revision_number' => inst[:cluster_revision_number],
            'number_of_nodes' => inst[:number_of_nodes],
            'cluster_nodes' => cluster_nodes,
            'publicly_accessible' => inst[:publicly_accessible],
            'encrypted' => inst[:encrypted],
        )

        icinga = Icinga2Host.new(address, address)
        # no real host to check, only service or sub nodes(cluster)
        icinga.check_command = 'dummy'
        icinga.display_name = "AWS #{@type} - #{address}"
        icinga.vars = {
            'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  module RDS
    extend Generic

    @client = Aws::RDS::Client.new
    @type = 'rds'
    # Get all hosts
    def self.hosts
      hosts = []
      # db_instances only (we dont use db_clusters currently)
      response = @client.describe_db_instances
      response[:db_instances].each do |inst|
        vars = Dictionary.new(@type, inst[:db_instance_identifier])
        vars.availability_zones = [inst[:availability_zone], inst[:secondary_availability_zone]]
        vars.instance_type = inst[:db_instance_class]
        port = inst[:endpoint][:port]
        hosted_zone_id = inst[:endpoint][:hosted_zone_id]
        address = inst[:endpoint][:address]

        vars.dns(address, nil)

        vars.add(
            @type,
            'engine' => inst[:engine],
            'db_instance_status' => inst[:db_instance_status],
            'master_username' => inst[:master_username],
            'db_name' => inst[:db_name],
            'port' => port,
            'hosted_zone_id' => hosted_zone_id,
            'allocated_storage' => inst[:allocated_storage],
            'instance_create_time' => inst[:instance_create_time],
            'preferred_maintenance_window' => inst[:preferred_maintenance_window],
            'multi_az' => inst[:multi_az],
            'engine_version' => inst[:engine_version],
            'auto_minor_version_upgrade' => inst[:auto_minor_version_upgrade],
            'license_model' => inst[:license_model],
            'iops' => inst[:iops],
            'publicly_accessible' => inst[:publicly_accessible],
            'storage_type' => inst[:storage_type],
            'db_instance_port' => inst[:db_instance_port],
            'db_cluster_identifier' => inst[:db_cluster_identifier],
            'storage_encrypted' => inst[:storage_encrypted],
            'monitoring_interval' => inst[:monitoring_interval],
            'enhanced_monitoring_resource_arn' => inst[:enhanced_monitoring_resource_arn],
            'monitoring_role_arn' => inst[:monitoring_role_arn],
            'db_instance_arn' => inst[:db_instance_arn],
            'timezone' => inst[:timezone],
        )

        icinga = Icinga2Host.new(address, address)
        # no real host to check, only service or sub nodes(cluster)
        icinga.check_command = 'dummy'
        icinga.display_name = "AWS #{@type} - #{address}"
        icinga.vars = {
            'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  module BatchJobQueue
    extend Generic

    @client = Aws::Batch::Client.new
    @type = 'batch_job_queue'
    # Get all hosts
    def self.hosts
      hosts = []

      response = @client.describe_job_queues
      response[:job_queues].each do |inst|
        job_queue_arn = inst[:job_queue_arn]
        job_queue_name = inst[:job_queue_name]
        vars = Dictionary.new(@type, job_queue_arn)

        vars.arn = job_queue_arn
        compute_environment_order = []
        inst[:compute_environment_order].each do |ceo|
          compute_environment_order.push({'order' => ceo[:order],
                                          'compute_environment' => ceo[:compute_environment]})
        end

        vars.add(
            @type,
            'job_queue_name' => job_queue_name,
            'state' => inst[:state],
            'status' => inst[:status],
            'priority' => inst[:priority],
            'compute_environment_order' => compute_environment_order,
        )

        icinga = Icinga2Host.new(job_queue_name, job_queue_arn)
        # no real host to check, only service or sub nodes(cluster)
        icinga.check_command = 'dummy'
        icinga.display_name = "AWS #{@type} - #{job_queue_arn}"
        icinga.vars = {
            'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end

  module DatabaseMigrationService
    extend Generic
    # see https://docs.aws.amazon.com/sdkforruby/api/Aws/DatabaseMigrationService/Client.html#describe_replication_instances-instance_method
    @client = Aws::DatabaseMigrationService::Client.new
    @type = 'dms'
    # Get all hosts
    def self.hosts
      hosts = []

      response = @client.describe_replication_instances
      response[:replication_instances].each do |inst|
        replication_instance_identifier = inst[:replication_instance_identifier]
        replication_instance_arn = inst[:replication_instance_arn]

      vars = Dictionary.new(@type, inst[:replication_instance_arn])
      vars.arn = replication_instance_arn

      vars.add(
          @type,
          'replication_instance_identifier' => inst[:replication_instance_identifier],
          'publicly_accessible' => inst[:publicly_accessible],
          'engine_version' => inst[:engine_version],
          'preferred_maintenance_window' => inst[:preferred_maintenance_window],
          'availability_zone' => inst[:availability_zone],
          'instance_create_time' => inst[:instance_create_time],
          'allocated_storage' => inst[:allocated_storage],
          'replication_instance_class' => inst[:replication_instance_class],
          'replication_instance_status' => inst[:replication_instance_status],
      )

        icinga = Icinga2Host.new(replication_instance_identifier, replication_instance_arn)
        # no real host to check, only service or sub nodes(cluster)
        icinga.check_command = 'dummy'
        icinga.display_name = "AWS #{@type} - #{replication_instance_identifier}"
        icinga.vars = {
            'aws' => vars.to_hash
        }
        hosts.push icinga
      end
      hosts
    end
  end
end

# Note: ensure values in vars are native Hash objects and not Structs!!
class Dictionary
  attr_reader :vars

  # AWS Service type, AWS unique name or id
  def initialize(type, id)
    @vars = {
      'type' => type,
      'id'   => id
    }
    # @todo when implementing multiple region support move to the specific line(s)
    self.region = ENV['AWS_REGION']
  end

  def arn=(value)
    @vars['arn'] = value
  end

  def region=(value)
    @vars['region'] = value
  end

  def ip(public, private)
    @vars['public_ip'] = public unless public.nil? || public.empty?
    @vars['private_ip'] = private unless private.nil? || private.empty?
  end

  def dns(public, private)
    @vars['public_dns'] = public unless public.nil? || public.empty?
    @vars['private_dns'] = private unless private.nil? || private.empty?
  end

  def tags(tags)
    @vars['tags'] = {}
    tags.each do |tag|
      @vars['tags'][tag.key] = tag.value
    end
  end

  def instance_type=(value)
    @vars['instance_type'] = value
  end

  def availability_zones=(value)
    value = [value] unless value.is_a?(Array)
    @vars['availability_zones'] = value
  end

  def add(key, val)
    @vars[key] = Dictionary.convert_non_basic_type_values_to_strings(val)
  end

  def self.convert_non_basic_type_values_to_strings(val)
    # dont convert the basic data types
    if val.nil? or val.is_a?(TrueClass) or val.is_a?(FalseClass) or val.is_a?(String) or val.is_a?(Integer) or
        val.is_a?(Float) or val.is_a?(Fixnum)
      val
    # check values in arrays and hashes
    elsif val.is_a?(Array)
      converted = []
      val.each do |value|
        converted.push(convert_non_basic_type_values_to_strings(value))
      end
      converted
    elsif val.is_a?(Hash)
      converted = {}
      val.each do |key, value|
        converted[key] = convert_non_basic_type_values_to_strings(value)
      end
      converted
    else
      # everything else will be cast to string (e.g. Time)
      val.to_s
    end
  end

  # required to compare native hash
  def to_hash
    @vars
  end
end
