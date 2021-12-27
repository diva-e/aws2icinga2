#!/usr/bin/env ruby
# loadpath by bundler
require 'rubygems'
require 'bundler/setup'
# load gems
require 'json'
require 'parallel'
# local libs
require_relative './lib/config.rb'
require_relative './lib/aws/service.rb'
require_relative './lib/icinga/api.rb'

icinga = Icinga2Api.new
raise 'Cannot talk with icinga2 api' unless icinga.check_running

# these are currently active in icinga
origin_hosts = {}
JSON.parse(icinga.hosts)['results'].each do |result|
  origin_hosts[result['name']] = Icinga2HostHelper.from_hash result['attrs']
end

begin
  hosts = Service.hosts
rescue => e
  puts e
  raise 'Failed to retrieve Hosts from AWS'
end

# speed up rest requests by parallel processing
# threads is required to modify vars
Parallel.each(hosts, in_threads: 8) do |host|
  if origin_hosts[host.name]
    if origin_hosts[host.name].to_hash != host.to_hash
      # make sure logging the diff does not break normal processing
      begin
        puts("Got different hashes for host " + host.name.to_s)
        puts("Diff detail:")
        Icinga2HostHelper.print_hash_diff_detail(origin_hosts[host.name].to_hash, host.to_hash)
      rescue => error
        puts("Encountered error while printing diff detail: " + error.to_s)
      end
      # icinga update does not re-evaluate vars, so delete and create
      icinga.delete_host(host.name, host)
      # give the icinga api time to delete the host, before re-creating it
      sleep 3
      icinga.create_host(host.name, host)
    end
  else
    icinga.create_host(host.name, host)
  end
  origin_hosts.delete(host.name)
end

# clean none existing hosts from icinga
Parallel.each(origin_hosts, in_threads: 8) do |host, _attrs|
  icinga.delete_host(host, _attrs)
end
