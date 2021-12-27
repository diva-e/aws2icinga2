require 'json'
class Icinga2Host
  attr_accessor :name, :address, :vars, :check_command, :zone
  attr_writer :display_name
  attr_reader :enable_notifications, :templates, :package

  def initialize(name, address)
    @name = name
    @address = address
    # defaults
    @display_name = nil
    @vars = {}
    @enable_notifications = true
    @check_command = 'hostalive'
    @zone = Config.icinga_zone
    @package = Config.package_name
    @templates = ['generic-host']
  end

  def enable_notifications=(value)
    raise 'Boolean required' if value != true && value != false
    @enable_notifications = value
  end

  def display_name
    @display_name.nil? ? @name : @display_name
  end

  def to_hash
    @vars.merge! Config.vars_host

    hash = {
      'check_command' => @check_command,
      'display_name' => display_name,
      'address' => @address,
      'enable_notifications' => @enable_notifications,
      'zone' => @zone,
      'vars' => @vars,
    }
    # package is used to differ accounts and region
    hash['vars']['package'] = @package
    hash
  end

  def to_json(*options)
    to_hash.to_json(*options)
  end
end

module Icinga2HostHelper
  def self.from_hash(attrs)
    host = Icinga2Host.new(attrs['__name'], attrs['address'])
    host.vars = attrs['vars']
    host.check_command = attrs['check_command']
    host.enable_notifications = attrs['enable_notifications']
    host.display_name = attrs['display_name']
    host.zone = attrs['zone']
    host
  end

  # Logs the difference between two hashes and returns true if a diff was found.
  # This should help figure out if a diff is valid or just because of type-casting by the conversion to and from json.
  def self.print_hash_diff_detail(hash1, hash2, context="host")
    found_diff = false
    if hash1 != hash2
      if hash1.is_a?(hash2.class)
        if hash1.is_a?(Hash)
          hash1.each do |key, value|
            if hash2.has_key? key
              new_context = context + "->" + key
              found_sub_diff = print_hash_diff_detail(value, hash2[key], new_context)
              if found_sub_diff and not found_diff
                found_diff = true
              end
            else
              puts("Missing key " + key.to_s + " context: " + context.to_s)
              found_diff = true
            end
          end
          hash2.each do |key, value|
            unless hash1.has_key? key
              puts("Additional key " + key.to_s + " context: " + context.to_s)
              found_diff = true
            end
          end
        elsif hash1.is_a?(Array)
          hash1.each do |value|
            unless hash2.include? value
              puts("Missing value " + value.to_s + " context: " + context.to_s)
              found_diff = true
            end
          end
          hash2.each do |value|
            unless hash1.include? value
              puts("Additional value " + value.to_s + " context: " + context.to_s)
              found_diff = true
            end
          end
        end
      else
        puts("Classes differ: " + hash1.class.to_s + " vs " + hash2.class.to_s + " context: " + context.to_s)
        found_diff = true
      end
    end
    found_diff
  end
end
