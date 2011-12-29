require "shelly/cli/command"
require "time"

module Shelly
  module CLI
    class Deploys < Command
      namespace :deploys
      include Helpers

      before_hook :logged_in?, :only => [:list, :show]
      before_hook :cloudfile_present?, :only => [:list, :show]

      desc "list", "Lists deploy logs"
      method_option :cloud, :type => :string, :aliases => "-c",
        :desc => "Specify which cloud to show deploy logs for"
      def list
        multiple_clouds(options[:cloud], "deploys list", "Select cloud to view deploy logs using:")
        logs = @app.deploy_logs
        unless logs.empty?
          say "Available deploy logs", :green
          logs.each do |log|
            log["failed"] ? say(" * #{log["created_at"]} (failed)") : say(" * #{log["created_at"]}")
          end
        else
          say "No deploy logs available"
        end
      rescue Client::APIError => e
        if e.unauthorized?
          say_error "You have no access to '#{@app.code_name}' cloud defined in Cloudfile"
        else
          say_error e.message
        end
      end

      desc "show LOG", "Show specific deploy log"
      method_option :cloud, :type => :string, :aliases => "-c",
        :desc => "Specify which cloud to show deploy logs for"
      def show(log = nil)
        specify_log(log)
        multiple_clouds(options[:cloud], "deploys show #{log}", "Select log and cloud to view deploy logs using:")
        content = @app.deploy_log(log)
        say "Log for deploy done on #{content["created_at"]}", :green
        if content["bundle_install"]
          say("Starting bundle install", :green); say(content["bundle_install"])
        end
        if content["whenever"]
          say("Starting whenever", :green); say(content["whenever"])
        end
        if content["callbacks"]
          say("Starting callbacks", :green); say(content["callbacks"])
        end
        if content["delayed_job"]
          say("Starting delayed job", :green); say(content["delayed_job"])
        end
        if content["thin_restart"]
          say("Starting thin", :green); say(content["thin_restart"])
        end
      rescue Client::APIError => e
        if e.unauthorized?
          say_error "You have no access to '#{@app.code_name}' cloud defined in Cloudfile"
        elsif e.message == "Log not found"
          say_error "Log not found, list all deploy logs using:", :with_exit => false
          say "  shelly deploys list #{cloud}"
          exit 1
        end
      end

      no_tasks do
        def specify_log(log)
          unless log
            say_error "Specify log by passing date value or to see last log use:", :with_exit => false
            say "  shelly deploys show last"
            exit 1
          end
        end
      end
    end
  end
end