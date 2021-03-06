require "shelly/cli/main"

module Shelly
  module CLI
    class Runner < Thor::Shell::Basic
      include Helpers
      attr_accessor :args

      def initialize(args = [])
        super()
        @args = args
      end

      def debug?
        args.include?("--debug") || ENV['SHELLY_DEBUG'] == "true"
      end

      def start
        show_windows_warning if Gem.win_platform?

        Shelly::CLI::Main.start(args)
      rescue SystemExit; raise
      rescue Client::UnauthorizedException
        raise if debug?
        say_error "You are not logged in. To log in use: `shelly login`"
      rescue Client::NotFoundException => e
        raise if debug? or e.resource != :cloud
        say_error "You have no access to '#{e.id}' cloud"
      rescue Client::GemVersionException => e
        raise if debug?
        say "Required shelly gem version: #{e.body["required_version"]}"
        say "Your version: #{VERSION}"
        if yes? "Update shelly gem?"
          system "gem install shelly"
        else
          say_error "Update shelly gem with `gem install shelly`"
        end
      rescue Interrupt
        raise if debug?
        say_new_line
        say_error "[canceled]"
      rescue Netrc::Error => e
        raise if debug?
        say_error e.message
      rescue HomeNotSetError
        raise if debug?
        say_error "Please set HOME environment variable."
      rescue Client::APIException => e
        raise if debug?
        say_error "You have found a bug in the shelly gem. We're sorry.",
          :with_exit => e.request_id.blank?
        say_error <<-eos
You can report it to support@shellycloud.com by describing what you wanted
to do and mentioning error id #{e.request_id}.
        eos
      rescue Exception
        raise if debug?
        say_error "Unknown error, to see debug information run command with --debug"
      end
    end
  end
end
