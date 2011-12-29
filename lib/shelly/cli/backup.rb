require "shelly/cli/command"
require "shelly/backup"
require "shelly/download_progress_bar"

module Shelly
  module CLI
    class Backup < Command
      namespace :backup
      include Helpers

      before_hook :logged_in?, :only => [:list, :get, :create]
      before_hook :cloudfile_present?, :only => [:list]

      desc "list", "List database backups"
      method_option :cloud, :type => :string, :aliases => "-c",
        :desc => "Specify which cloud to list backups for"
      def list
        multiple_clouds(options[:cloud], "backup list", "Select cloud to view database backups for using:")
        backups = @app.database_backups
        if backups.present?
          to_display = [["Filename", "|  Size"]]
          backups.each do |backup|
            to_display << [backup.filename, "|  #{backup.human_size}"]
          end

          say "Available backups:", :green
          say_new_line
          print_table(to_display, :ident => 2)
        else
          say "No database backups available"
        end
      rescue Client::APIError => e
        if e.unauthorized?
          say_error "You have no access to '#{@app.code_name}' cloud defined in Cloudfile"
        else
          say_error e.message
        end
      end

      method_option :cloud, :type => :string, :aliases => "-c", :desc => "Specify which cloud list backups for"
      desc "get [FILENAME]", "Downloads specified or last backup to current directory"
      def get(handler = "last")
        multiple_clouds(options[:cloud], "backup get [FILENAME]", "Select cloud for which you want download backup")

        backup = @app.database_backup(handler)
        bar = Shelly::DownloadProgressBar.new(backup.size)
        backup.download(bar.progress_callback)

        say_new_line
        say "Backup file saved to #{backup.filename}", :green
      rescue Client::APIError => e
        if e.not_found?
          say_error "Backup not found", :with_exit => false
          say "You can list available backups with 'shelly backup list' command"
        else
          raise e
        end
      end

      desc "create [KIND]", "Creates current snapshot of given database. Default: all databases."
      method_option :cloud, :type => :string, :aliases => "-c",
        :desc => "Specify which cloud to create database snapshot for"
      def create(kind = nil)
        multiple_clouds(options[:cloud], "backup create", "Select cloud to create snapshot of database")
        @app.request_backup(kind)
        say "Backup requested. It can take up to several minutes for" +
          "the backup process to finish and the backup to show up in backups list.", :green
      rescue Client::APIError => e
        if e.unauthorized?
          say_error "You have no access to '#{@app.code_name}' cloud defined in Cloudfile"
        else
          say_error e.message
        end
      end
    end
  end
end