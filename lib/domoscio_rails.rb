
require 'net/https'
require 'cgi/util'
require 'multi_json'

# helpers
require 'domoscio_rails/version'
require 'domoscio_rails/json'
require 'domoscio_rails/errors'
require 'domoscio_rails/authorization_token'

# resources
require 'domoscio_rails/http_calls'
require 'domoscio_rails/resource'
require 'domoscio_rails/adaptative/deterministic/path_rule'
require 'domoscio_rails/adaptative/deterministic/rule_input'
require 'domoscio_rails/adaptative/deterministic/rule_output'
require 'domoscio_rails/adaptative/deterministic/rule_condition'
require 'domoscio_rails/adaptative/predictive/objective'
require 'domoscio_rails/adaptative/predictive/objective_student'
require 'domoscio_rails/adaptative/predictive/objective_knowledge_node'
require 'domoscio_rails/adaptative/predictive/objective_knowledge_node_student'
require 'domoscio_rails/adaptative/recommendation'
require 'domoscio_rails/path/learning_path'
require 'domoscio_rails/content/content'
require 'domoscio_rails/content/knowledge_node_content'
require 'domoscio_rails/student/student'
require 'domoscio_rails/student/student_cluster'
require 'domoscio_rails/knowledge/knowledge_graph'
require 'domoscio_rails/knowledge/knowledge_edge'
require 'domoscio_rails/knowledge/knowledge_node'
require 'domoscio_rails/metadata/tag'
require 'domoscio_rails/metadata/tagging'
require 'domoscio_rails/metadata/tag_set'
require 'domoscio_rails/metadata/tag_edge'
require 'domoscio_rails/data/knowledge_node_student'
require 'domoscio_rails/data/event'
require 'domoscio_rails/data/learning_session'
require 'domoscio_rails/utils/review_util'
require 'domoscio_rails/utils/gameplay_util'
require 'domoscio_rails/utils/alerts_util'
require 'domoscio_rails/utils/recommendation_util'
require 'domoscio_rails/metadata/delta_object'

module DomoscioRails

  class Configuration
    attr_accessor :preproduction, :test, :dev, :root_url,
    :client_id, :client_passphrase, :client_identifier,
    :temp_dir, :disabled, :version

    def disabled
      @disabled || false
    end

    def preproduction
      @preproduction || false
    end

    def test
      @test || false
    end

    def dev
      @dev || false
    end

    def version
      @version || 1
    end

    def root_url
      if @preproduction == true
        if @test == true
          @root_url || "https://domoscio-adaptive-engine-staging.azurewebsites.net"
        elsif @dev == true
          @root_url || "https://domoscio-adaptive-engine-preprod.azurewebsites.net"
        else
          @root_url || "https://domoscio-adaptive-engine.azurewebsites.net"
        end
      else
        @root_url || "http://localhost:3001"
      end
    end
  end

  class << self
    attr_accessor :configuration
  end

  def self.configure
    self.configuration ||= Configuration.new
    yield configuration
  end

  def self.api_uri(url='')
    URI(configuration.root_url + url)
  end

  #
  # - +method+: HTTP method; lowercase symbol, e.g. :get, :post etc.
  # - +url+: the part after Configuration#root_url
  # - +params+: hash; entity data for creation, update etc.; will dump it by JSON and assign to Net::HTTPRequest#body
  # - +filters+: hash; pagination params etc.; will encode it by URI and assign to URI#query
  # - +headers+: hash; request_headers by default
  # - +before_request_proc+: optional proc; will call it passing the Net::HTTPRequest instance just before Net::HTTPRequest#request
  #
  # Raises DomoscioRails::ResponseError if response code != 200.
  #
  def self.request(method, url, params={}, filters={}, headers = request_headers, before_request_proc = nil)
    return false if @disabled
    uri = api_uri(url)
    uri.query = URI.encode_www_form(filters) unless filters.empty?

    res = DomoscioRails.send_request(uri, method, params, headers, before_request_proc)

    # decode json data
    begin
      data = DomoscioRails::JSON.load(res.body.nil? ? '' : res.body)
      unless (res.kind_of? Net::HTTPClientError) || (res.kind_of? Net::HTTPServerError)
        DomoscioRails::AuthorizationToken::Manager.storage.store({access_token: res['Accesstoken'], refresh_token: res['Refreshtoken']})
      end
    rescue MultiJson::LoadError
      data = {}
    end

    if res['Total'] && !filters[:page]
      pagetotal = (res['Total'].to_i / res['Per-Page'].to_f).ceil

      for j in 2..pagetotal
        params = params.merge({page: j})
        res = DomoscioRails.send_request(uri, method, params, headers, before_request_proc)

        # decode json data
        begin
          data += DomoscioRails::JSON.load(res.body.nil? ? '' : res.body)
          data.flatten!
        rescue MultiJson::LoadError
          data = {}
        end

      end
    end

    ############### TEMP!!!! #######################################################
    #pp method, uri.request_uri, params #, filters, headers
    #pp res, data
    #puts

    # if (!(res.is_a? Net::HTTPOK))
    #   ex = DomoscioRails::ResponseError.new(uri, res.code, data)
    #   ############## TEMP!!!! ########################################################
    #   #pp ex, data
    #   raise ex
    # end

    # copy pagination info if any
    # ['x-number-of-pages', 'x-number-of-items'].each { |k|
#       filters[k.gsub('x-number-of-', 'total_')] = res[k].to_i if res[k]
#     }

    data
  end


  def self.send_request(uri, method, params, headers, before_request_proc)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http| # , use_ssl: uri.scheme == 'https') do |http|
      req = Net::HTTP::const_get(method.capitalize).new(uri.request_uri, headers)
      req.body = DomoscioRails::JSON.dump(params)
      before_request_proc.call(req) if before_request_proc
      http.request req
    end
  end

  private

  def self.user_agent
    @uname ||= get_uname

    {
      bindings_version: DomoscioRails::VERSION,
      lang: 'ruby',
      lang_version: "#{RUBY_VERSION} p#{RUBY_PATCHLEVEL} (#{RUBY_RELEASE_DATE})",
      platform: RUBY_PLATFORM,
      uname: @uname
    }
  end

  def self.get_uname
    `uname -a 2>/dev/null`.strip if RUBY_PLATFORM =~ /linux|darwin/i
  rescue Errno::ENOMEM
    'uname lookup failed'
  end

  def self.request_headers
    auth_token = DomoscioRails::AuthorizationToken::Manager.get_token
    client_identifier = DomoscioRails.configuration.client_identifier

    if !auth_token.is_a? String
      headers = {
        'user_agent' => "DomoscioRails V2 RubyBindings/#{DomoscioRails::VERSION}",
        'AccessToken' => "#{auth_token[:access_token]}",
        'RefreshToken' => "#{auth_token[:refresh_token]}",
        'Content-Type' => 'application/json'
      }
    else
      headers = {
        'user_agent' => "DomoscioRails V2 RubyBindings/#{DomoscioRails::VERSION}",
        'Authorization' => "Token token=#{DomoscioRails.configuration.client_passphrase}",#"#{auth_token['token_type']} #{auth_token['access_token']}",
        'Content-Type' => 'application/json'
      }
    end
    headers['VizToken'] = client_identifier if !client_identifier.nil?

    headers

  end


end
