require 'rest-client'

class Icinga2Api
  API_URL_OBJ_HOSTS = '/objects/hosts'.freeze
  attr_accessor :node_name, :api_username, :api_password, :api_url_base, :package

  # define icinga config package, these is required for account seperation (default of icinga is _api)
  def initialize
    @node_name = Socket.gethostbyname(Socket.gethostname).first
    @api_username = Config.icinga_api_username
    @api_password = Config.icinga_api_password
    @api_url_base = Config.icinga_api_url_base
    @package = Config.package_name
  end

  # prepare the rest client ssl stuff
  def prepare_rest_client(api_url)
    # check whether pki files are there, otherwise use basic auth
    if File.file?('pki/' + @node_name + '.crt')
      # puts "PKI found, using client certificates for connection to Icinga 2 API"
      cert_file = File.read('pki/' + @node_name + '.crt')
      key_file = File.read('pki/' + @node_name + '.key')
      ca_file = File.read('pki/ca.crt')

      cert = OpenSSL::X509::Certificate.new(cert_file)
      key = OpenSSL::PKey::RSA.new(key_file)

      options = { ssl_client_cert: cert, ssl_client_key: key, ssl_ca_file: ca_file, verify_ssl: OpenSSL::SSL::VERIFY_NONE }
    else
      # puts "PKI not found, using basic auth for connection to Icinga 2 API"

      options = { user: @api_username, password: @api_password, verify_ssl: OpenSSL::SSL::VERIFY_NONE }
    end
    res = RestClient::Resource.new(URI.escape(api_url), options)
    res
  end

  # fetch global status to see if api is available
  def check_running
    api_url = @api_url_base + '/status/IcingaApplication'
    rest_client = prepare_rest_client(api_url)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

    puts "Checking the availability of the Icinga 2 API at #{api_url}."

    begin
      response = rest_client.get(headers)
      return true if response['results']
      return false
      # puts 'Status: ' + (JSON.pretty_generate JSON.parse(response.body))
    rescue => e
      puts e
      return false
    end
  end

  # list, GET
  def hosts
    filter = "?filter=host.vars.package==\"#{@package}\""
    api_url = @api_url_base + API_URL_OBJ_HOSTS + '/' + filter
    rest_client = prepare_rest_client(api_url)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

    puts "Icinga 2: Getting hosts by package '#{@package}'."

    begin
      response = rest_client.get(headers)
    rescue => e
      puts e
      nil unless e.response
      return e.response
    end
    response
  end

  # list, GET
  def get_host(name)
    api_url = @api_url_base + API_URL_OBJ_HOSTS + "/#{name}"
    rest_client = prepare_rest_client(api_url)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

    puts "Icinga 2: Getting host '#{name}'."

    begin
      response = rest_client.get(headers)
    rescue => e
      puts e
      return nil unless e.response
      return e.response
    end
    # puts response
    response
  end

  # create, PUT
  def create_host(name, host)
    api_url = @api_url_base + API_URL_OBJ_HOSTS + "/#{name}"
    rest_client = prepare_rest_client(api_url)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    # hardcode the required check_command attribute
    attrs = {
      'attrs' => host,
      'templates' => host.templates
    }

    puts "Icinga 2: Creating host '#{name}' with attributes: '" + attrs.to_json + "'."

    begin
      response = rest_client.put(attrs.to_json, headers)
    rescue => e
      puts e
      return nil unless e.response
      return e.response
    end
    response
  end

  # update, POST
  # useless since attribute changes ar not permanent... https://dev.icinga.org/issues/11501
  def update_host(name, host)
    host.package = @package
    api_url = @api_url_base + API_URL_OBJ_HOSTS + "/#{name}"
    rest_client = prepare_rest_client(api_url)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }
    attrs = {
      'attrs' => host
    }

    puts "Icinga 2: Updating host '#{name}' with attributes: '" + attrs.to_json + "'."

    begin
      response = rest_client.post(attrs.to_json, headers)
    rescue => e
      puts e
      return nil unless e.response
      return e.response
    end
    response
  end

  # delete, DELETE
  def delete_host(name, host)
    api_url = @api_url_base + API_URL_OBJ_HOSTS + "/#{name}?cascade=1" # applied services require cascading delete
    rest_client = prepare_rest_client(api_url)
    headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

    attrs = {
        'attrs' => host
    }
    puts "Icinga 2: Deleting host '#{name}' with attributes: '" + attrs.to_json + "'."

    begin
      response = rest_client.delete(headers)
    rescue => e
      puts e
      return nil unless e.response
      return e.response
      # silently ignore errors with non-existing objects
      # puts "Errors deleting host '#{name}'."
    end

    # we use cascading delete, but anyways
    puts response.body if response && response.code != 200

    response
  end
end
