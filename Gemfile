# frozen_string_literal: true
# A sample Gemfile
source 'https://rubygems.org'

gem 'aws-sdk', '~> 2'
gem 'parallel'

group :test do
  gem 'test-unit'
end

if RUBY_VERSION.to_i == 1
  # ruby 1.9.3
  gem 'json', '~> 1'
  gem 'rest_client'
else
  gem 'rubocop', :groups => [:development, :test]
  # ruby > 2
  gem 'rest-client'
  gem 'json'
end
