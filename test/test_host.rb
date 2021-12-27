require 'test/unit'

ENV['CONFIG_PACKAGE_NAME'] = 'test_phpunit_package'
ENV['CONFIG_SERVICES'] = 'test_phpunit_service'
ENV['CONFIG_VARS_HOST'] = '{"teams": ["test_phpunit"]}'
ENV['ICINGA_ZONE'] = 'test_phpunit_worker'
ENV['AWS_REGION'] = 'test_phpunit_region'

require_relative '../lib/icinga/host.rb'
require_relative '../lib/config.rb'
require_relative '../lib/aws/service.rb'

class TestHost < Test::Unit::TestCase

  def test_to_from_hash
    host = Icinga2Host.new("host_name", "host_address")
    host.check_command = 'dummy'
    host.display_name = "Test host_name"

    vars = Dictionary.new("test_host_vars_type", "test_host_vars_id")
    vars.ip("127.0.0.1", "127.0.0.1")
    vars.dns("public.test.host.unit.test.org", "private.test.host.unit.test.org")

    vars.availability_zones = "test_single_availability_zone"
    vars.instance_type = "test_very_big_instance"
    vars.add(
        'unit_test_type',
        'test_int' => 123,
        'test_float' => 1.23,
        'test_string' => "test_string_123",
        'test_string_int_value' => "123",
        'test_boolean' => TRUE,
        'test_nil' => nil,
        'test_timestamp' => Time.new(2018, 4, 17, 19, 30, 46),
        'test_array' => ['array_element_1', 123, TRUE, Time.new(2018, 4, 17, 19, 30, 46)],
        'test_hash' => {
            'test_key_1' => 'test_element_1',
            'test_key_2' => 123, 'test_key_3' => TRUE,
            'test_key_4' => Time.new(2018, 4, 17, 19, 30, 46),
            'test_key_5' => nil,
        }
    )

    host.vars = {
        'aws' => vars.to_hash
    }

    host_json = host.to_json

    host_from_hash = Icinga2HostHelper.from_hash(JSON.parse(host_json))

    assert_equal(host.to_hash, host_from_hash.to_hash)
  end

  def test_print_hash_diff_detail
    host = Icinga2Host.new("host_name", "host_address")
    host.check_command = 'dummy'
    host.display_name = "Test host_name"

    vars = Dictionary.new("test_host_vars_type", "test_host_vars_id")
    vars.ip("127.0.0.1", "127.0.0.1")
    vars.dns("public.test.host.unit.test.org", "private.test.host.unit.test.org")

    vars.availability_zones = "test_single_availability_zone"
    vars.instance_type = "test_very_big_instance"
    vars.add(
        'unit_test_type',
        'test_int' => 123,
        'test_float' => 1.23,
        'test_string' => "test_string_123",
        'test_string_int_value' => "123",
        'test_boolean' => TRUE,
        'test_nil' => nil,
        'test_timestamp' => Time.new(2018, 4, 17, 19, 30, 46),
        'test_array' => ['array_element_1', 123, TRUE, Time.new(2018, 4, 17, 19, 30, 46)],
        'test_hash' => {
            'test_key_1' => 'test_element_1',
            'test_key_2' => 123, 'test_key_3' => TRUE,
            'test_key_4' => Time.new(2018, 4, 17, 19, 30, 46),
            'test_key_5' => nil,
        }
    )

    host.vars = {
        'aws' => vars.to_hash
    }

    host2 = Icinga2Host.new("host_name", "host_address")
    host2.check_command = 'dummy'
    host2.display_name = "Test host_name"

    vars = Dictionary.new("test_host_vars_type", "test_host_vars_id")
    vars.ip("127.0.0.1", "127.0.0.1")
    vars.dns("public.test.host.unit.test.org", "private.test.host.unit.test.org")

    vars.availability_zones = ["test_availability_zone_different", "second_availability_zone"]
    vars.instance_type = "test_very_big_instance"
    vars.add(
        'unit_test_type',
        'test_int' => 123,
        'test_float' => 1.23,
        'test_string' => "test_string_123",
        'test_string_int_value' => "123",
        'test_boolean' => TRUE,
        'test_nil' => nil,
        'test_additional_key' => "additional_value",
        'test_timestamp' => Time.new(2018, 4, 17, 19, 30, 46),
        'test_array' => ['array_element_1', 123, TRUE, Time.new(2018, 4, 17, 19, 30, 46)],
        'test_hash' => {
            'test_key_1' => 'test_element_1',
            #'test_key_2' => 123, 'test_key_3' => TRUE,  # @test: two missing keys here
            'test_key_4' => Time.new(2018, 4, 17, 19, 30, 46),
            'test_key_5' => nil,
            'test_additional_key' => "additional_value",
        }
    )

    host2.vars = {
        'aws' => vars.to_hash
    }

    found_diff = Icinga2HostHelper.print_hash_diff_detail(host.to_hash, host2.to_hash)

    assert_true(found_diff)
  end

end