require 'test/unit'

ENV['CONFIG_PACKAGE_NAME'] = 'aws-production'
ENV['CONFIG_SERVICES'] = 'redshift'
ENV['CONFIG_VARS_HOST'] = '{"teams": ["devops"]}'
ENV['ICINGA_ZONE'] = 'worker'
ENV['AWS_REGION'] = 'eu-central-1'

require_relative '../lib/icinga/host.rb'
require_relative '../lib/config.rb'
require_relative '../lib/aws/service.rb'

class TestService < Test::Unit::TestCase

  def test_convert_non_basic_type_values_to_strings
    values = [
        {"input" => "test_string", "expected" => "test_string"},
        {"input" => "123", "expected" => "123"},
        {"input" => 123, "expected" => 123},
        {"input" => 123.123, "expected" => 123.123},
        {"input" => TRUE, "expected" => TRUE},
        {"input" => FALSE, "expected" => FALSE},
        {"input" => nil, "expected" => nil},
        {"input" => Time.new(2018, 8, 17, 19, 30, 46), "expected" => Time.new(2018, 8, 17, 19, 30, 46).to_s},
        {"input" => ["test_string", 123, TRUE, Time.new(2018, 8, 17, 19, 30, 46)],
         "expected" => ["test_string", 123, TRUE, Time.new(2018, 8, 17, 19, 30, 46).to_s]},
        {"input" => {"test" => ["test_string", 123, TRUE, Time.new(2018, 8, 17, 19, 30, 46)],
                     "test2" => ["test_string", 123, TRUE, Time.new(2018, 8, 17, 19, 30, 46)]},
         "expected" => {"test" => ["test_string", 123, TRUE, Time.new(2018, 8, 17, 19, 30, 46).to_s],
                        "test2" => ["test_string", 123, TRUE, Time.new(2018, 8, 17, 19, 30, 46).to_s]}},
    ]
    
    values.each do |value_dict|
      expected = value_dict["expected"]
      actual = Dictionary.convert_non_basic_type_values_to_strings(value_dict["input"])
      self.assert_equal(expected, actual, "input: " + value_dict["input"].to_s)
    end
  end

end