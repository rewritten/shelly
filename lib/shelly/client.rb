require "rest_client"
require "json"

module Shelly
  class Client
    class APIError < Exception
      attr_reader :status_code
      
      def initialize(response_body, status_code)
        @response = JSON.parse(response_body)
        @status_code = status_code
      end

      def message
        @response["message"]
      end

      def errors
        @response["errors"]
      end

      def url
        @response["url"]
      end

      def validation?
        message == "Validation Failed"
      end
      
      def not_found?
        status_code == 404
      end

      def unauthorized?
        # FIXME: Return unauthorized if user has no access to cloud, checked by 401 status code
        #        Return 404 if child of app doesn't exist, should be fixed in API
        message == "Unauthorized" || message =~ /Cloud .+ not found/
      end

      def each_error
        @response["errors"].each do |index,message|
          yield index.gsub('_',' ').capitalize + " " + message
        end
      end
    end

    attr_reader :email, :password

    def initialize(email = nil, password = nil)
      @email = email
      @password = password
    end

    def api_url
      ENV["SHELLY_URL"] || "https://admin.winniecloud.com/apiv2"
    end

    def shellyapp_url
      get("/shellyapp")["url"]
    end

    def register_user(email, password, ssh_key)
      post("/users", :user => {:email => email, :password => password, :ssh_key => ssh_key})
    end

    def token
      get("/token")
    end

    def app_configs(cloud)
      get("/apps/#{cloud}/configs")
    end

    def app_config(cloud, id)
      get("/apps/#{cloud}/configs/#{id}")
    end

    def app_create_config(cloud, path, content)
      post("/apps/#{cloud}/configs", :config => {:path => path, :content => content})
    end

    def app_update_config(cloud, id, content)
      put("/apps/#{cloud}/configs/#{id}", :config => {:content => content})
    end

    def app_delete_config(cloud, id)
      delete("/apps/#{cloud}/configs/#{id}")
    end

    def send_invitation(cloud, email)
      post("/apps/#{cloud}/collaborations", :email => email)
    end

    def create_app(attributes)
      post("/apps", :app => attributes)
    end

    def delete_app(code_name)
      delete("/apps/#{code_name}")
    end

    def add_ssh_key(ssh_key)
      post("/ssh_key", :ssh_key => ssh_key)
    end

    def start_cloud(cloud)
      put("/apps/#{cloud}/start")
    end

    def stop_cloud(cloud)
      put("/apps/#{cloud}/stop")
    end

    def apps
      get("/apps")
    end

    def deploy_logs(cloud)
      get("/apps/#{cloud}/deploys")
    end

    def deploy_log(cloud, log)
      get("/apps/#{cloud}/deploys/#{log}")
    end

    def application_logs(cloud)
      get("/apps/#{cloud}/logs")
    end

    def database_backups(code_name)
      get("/apps/#{code_name}/database_backups")
    end
    
    def database_backup(code_name, handler)
      get("/apps/#{code_name}/database_backups/#{handler}")
    end

    def request_backup(code_name, kind = nil)
      post("/apps/#{code_name}/database_backups", :kind => kind)
    end

    def ssh_key_available?(ssh_key)
      get("/users/new", :ssh_key => ssh_key)
    end

    def app_users(cloud)
      get("/apps/#{cloud}/users")
    end

    def app_ips(cloud)
      get("/apps/#{cloud}/ips")
    end

    def post(path, params = {})
      request(path, :post, params)
    end

    def put(path, params = {})
      request(path, :put, params)
    end

    def get(path, params = {})
      request(path, :get, params)
    end

    def delete(path, params = {})
      request(path, :delete, params)
    end
    
    def download_backup(cloud, filename, progress_callback = nil)
      File.open(filename, "w") do |out|
        process_response = lambda do |response|
          response.read_body do |chunk|
            out.write(chunk)
            progress_callback.call(chunk.size) if progress_callback
          end
        end

        options = request_parameters("/apps/#{cloud}/database_backups/#{filename}", :get)
        options = options.merge(:block_response => process_response, 
          :headers => {:accept => "application/x-gzip"})
      
        RestClient::Request.execute(options)
      end
    end

    def request(path, method, params = {})
      options = request_parameters(path, method, params)
      RestClient::Request.execute(options) do |response, request|
        process_response(response)
      end
    end

    def headers
      {:accept          => :json,
       :content_type    => :json,
       "shelly-version" => Shelly::VERSION}
    end

    def http_basic_auth_options
      @email ? {:user => @email, :password => @password} : {}
    end

    def request_parameters(path, method, params = {})
      {:method   => method,
       :url      => "#{api_url}#{path}",
       :headers  => headers,
       :payload  => params.to_json
      }.merge(http_basic_auth_options)
    end

    def process_response(response)
      if [401, 404, 422, 500].include?(response.code)
        raise APIError.new(response.body, response.code)
      end

      response.return!
      JSON.parse(response.body)
    end
  end
end

