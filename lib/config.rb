require 'json'
# Parse and check configs
module Config
  def self.initialize
    # required values
    ensure_exist 'CONFIG_PACKAGE_NAME'
    @package_name = ENV['CONFIG_PACKAGE_NAME']

    ensure_exist 'CONFIG_SERVICES'
    @services = ENV['CONFIG_SERVICES'].split(',')

    # optional values
    @vars_host = JSON.parse ENV['CONFIG_VARS_HOST'] if ENV['CONFIG_VARS_HOST'] && !ENV['CONFIG_VARS_HOST'].empty?
    @ec2_ignore_autoscaling = ENV['CONFIG_EC2_IGNORE_AUTOSCALING'] ? true : false
    @ec2_tag_name = ENV['CONFIG_EC2_TAG_NAME'] if ENV['CONFIG_EC2_TAG_NAME'] && !ENV['CONFIG_EC2_TAG_NAME'].empty?
    @icinga_zone = ENV['ICINGA_ZONE'] ? ENV['ICINGA_ZONE'] : ''

    @ignore_tags = {}
    if ENV['CONFIG_IGNORE_TAGS'] && !ENV['CONFIG_IGNORE_TAGS'].empty?
      ENV['CONFIG_IGNORE_TAGS'].split(',').each do |tag|
        split = tag.split('=')
        next if split.length != 2
        @ignore_tags[split[0]] = split[1]
      end
    end
  end

  def self.ensure_exist(name)
    raise "Please set environment variable #{name}" unless ENV[name]
    raise "Please set a value for variable #{name}" if ENV[name].empty?
  end

  def self.package_name
    @package_name
  end

  def self.services
    @services
  end

  def self.vars_host
    @vars_host
  end

  def self.ec2_ignore_autoscaling
    @ec2_ignore_autoscaling
  end

  def self.ec2_tag_name
    @ec2_tag_name
  end

  def self.ignore_tags
    @ignore_tags
  end

  def self.icinga_zone
    @icinga_zone
  end

  def self.icinga_api_username
    ENV['ICINGA_API_USERNAME'] || 'root'
  end

  def self.icinga_api_password
    ENV['ICINGA_API_PASSWORD'] || 'icinga'
  end

  def self.icinga_api_url_base
    ENV['ICINGA_API_URL_BASE'] || 'https://127.0.0.1:5665/v1'
  end
end
Config.initialize
