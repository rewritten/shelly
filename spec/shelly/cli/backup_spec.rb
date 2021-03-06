require "spec_helper"
require "shelly/cli/backup"
require "shelly/download_progress_bar"
require "open3"

describe Shelly::CLI::Backup do
  before do
    @backup = Shelly::CLI::Backup.new
    Shelly::CLI::Backup.stub(:new).and_return(@backup)
    @client = mock
    @client.stub(:authorize!)
    Shelly::Client.stub(:new).and_return(@client)
    FileUtils.mkdir_p("/projects/foo")
    Dir.chdir("/projects/foo")
    File.open("Cloudfile", 'w') {|f| f.write("foo-staging:\n") }
    @app = Shelly::App.new("foo-staging")
    Shelly::App.stub(:new).and_return(@app)
  end

  describe "#list" do
    before do
      FileUtils.mkdir_p("/projects/foo")
      Dir.chdir("/projects/foo")
      File.open("Cloudfile", 'w') { |f| f.write("foo-staging:\n") }
      $stdout.stub(:puts)
    end

    it "should ensure user has logged in" do
      hooks(@backup, :list).should include(:logged_in?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @client.should_receive(:database_backups).with("foo-staging").and_return(
         [{"filename" => "backup.postgre.tar.gz", "human_size" => "10kb",
         "size" => 12345, "state" => "completed"}])
      @backup.should_receive(:multiple_clouds).and_return(@app)
      invoke(@backup, :list)
    end

    it "should take cloud from command line for which to show backups" do
      stub_const("Shelly::Backup::LIMIT", 1)
      @client.should_receive(:database_backups).with("foo-staging").and_return(
        [{"filename" => "backup.postgre.tar.gz", "human_size" => "10kb",
          "size" => 12345, "state" => "completed"},
         {"filename" => "backup.mongo.tar.gz", "human_size" => "22kb",
          "size" => 333, "state" => "in_progress"}])
      $stdout.should_not_receive(:puts).with("Limiting the number of backups to 1.")
      $stdout.should_receive(:puts).with("\n")
      $stdout.should_receive(:puts).with("  Filename               |  Size  |  State")
      $stdout.should_receive(:puts).with("  backup.postgre.tar.gz  |  10kb  |  completed")
      $stdout.should_receive(:puts).with("  backup.mongo.tar.gz    |  22kb  |  in progress")
      @backup.options = {:cloud => "foo-staging", :all => true}
      invoke(@backup, :list)
    end

    it "should show --all option if not present" do
      stub_const("Shelly::Backup::LIMIT", 1)
      $stdout.should_receive(:puts).with(green "Showing only last 1 backups.")
      $stdout.should_receive(:puts).with("Use --all or -a option to list all backups.")
      @client.should_receive(:database_backups).with("foo-staging").and_return(
          [{"filename" => "backup.postgre.tar.gz", "human_size" => "10kb",
            "size" => 12345, "state" => "completed"},
           {"filename" => "backup.mongo.tar.gz", "human_size" => "22kb",
            "size" => 333, "state" => "in_progress"}])
      invoke(@backup, :list)
    end

    describe "#get" do
      before do
        @client.stub(:download_file)
        @bar = mock(:progress_callback => @callback, :finish => true)
        Shelly::DownloadProgressBar.stub(:new).and_return(@bar)
        @client.stub(:database_backup).and_return({"filename" => "better.tar.gz", "size" => 12345})
        @client.stub(:download_backup_url).with("foo-staging", "better.tar.gz").
          and_return("https://backups.example.com")
        $stdout.stub(:puts)
      end

      it "should ensure user has logged in" do
        hooks(@backup, :get).should include(:logged_in?)
      end

      it "should have a 'download' alias" do
        @client.should_receive(:download_file).with("foo-staging", "better.tar.gz",
                                                    "https://backups.example.com",
                                                    @bar.progress_callback)
        invoke(@backup, :download, "better.tar.gz")
      end

      # multiple_clouds is tested in main_spec.rb in describe "#start" block
      it "should ensure multiple_clouds check" do
        @client.should_receive(:download_backup_url).with("foo-staging", "better.tar.gz")
        @client.should_receive(:database_backup).with("foo-staging", "last")
        @backup.should_receive(:multiple_clouds).and_return(@app)
        invoke(@backup, :get)
      end

      it "should fetch backup size and initialize download progress bar" do
        @client.stub(:database_backup).and_return({"filename" => "better.tar.gz", "size" => 333})
        Shelly::DownloadProgressBar.should_receive(:new).with(333).and_return(@bar)

        invoke(@backup, :get)
      end

      it "should fetch given backup file itself" do
        @client.should_receive(:download_file).with("foo-staging", "better.tar.gz",
                                                    "https://backups.example.com",
                                                    @bar.progress_callback)
        invoke(@backup, :get, "better.tar.gz")
      end

      it "should show info where file has been saved" do
        $stdout.should_receive(:puts)
        $stdout.should_receive(:puts).with(green "Backup file saved to better.tar.gz")
        @client.should_receive(:download_file).with("foo-staging", "better.tar.gz",
                                                    "https://backups.example.com",
                                                    @bar.progress_callback)
        invoke(@backup, :get, "last")
      end

      context "on backup not found" do
        it "it should display error message" do
          exception = Shelly::Client::NotFoundException.new({"resource" => "backup"})
          @client.stub(:database_backup).and_raise(exception)
          $stdout.should_receive(:puts).with(red "Backup not found")
          $stdout.should_receive(:puts).with("You can list available backups with `shelly backup list` command")
          invoke(@backup, :get, "better.tar.gz")
        end
      end

      context "on unsupported exception" do
        it "should re-raise it" do
          exception = Shelly::Client::APIException.new
          @client.stub(:database_backup).and_raise(exception)
          $stdout.should_not_receive(:puts).with(red "Backup not found")
          $stdout.should_not_receive(:puts).with("You can list available backups with `shelly backup list` command")
          lambda {
            invoke(@backup, :get, "better.tar.gz")
          }.should raise_error(Shelly::Client::APIException)
        end
      end
    end
  end

  describe "create" do
    before do
      FileUtils.mkdir_p("/projects/foo")
      Dir.chdir("/projects/foo")
      $stdout.stub(:puts)
      @app = mock(:backup_databases => ['postgresql', 'mongodb'], :code_name => "foo-staging")
      Shelly::App.stub(:new).and_return(@app)
      @cloudfile = mock(:present? => true, :clouds => [@app])
      Shelly::Cloudfile.stub(:new).and_return(@cloudfile)
    end

    it "should ensure user has logged in" do
      hooks(@backup, :create).should include(:logged_in?)
    end

    context "for aliases" do
      it "should respond to 'new' alias" do
        @app.should_receive(:request_backup)
        invoke(@backup, :new)
      end

      it "should ensure user has logged in for 'new' alias" do
        hooks(@backup, :new).should include(:logged_in?)
      end
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @app.stub(:request_backup)
      @backup.should_receive(:multiple_clouds).and_return(@app)
      invoke(@backup, :create)
    end

    it "should display errors and exit 1 when kind is not valid" do
      response = {"errors" => [["kind", "is invalid"]]}
      exception = Shelly::Client::ValidationException.new(response)
      @app.should_receive(:request_backup).and_raise(exception)
      $stdout.should_receive(:puts).with(red "Kind is invalid")
      lambda { invoke(@backup, :create) }.should raise_error(SystemExit)
    end

    it "should backup db specified by cli" do
      @app.should_receive(:request_backup).with('postgresql')
      invoke(@backup, :create, "postgresql")
    end

    it "should backup all dbs in cloudfile" do
      @app.should_receive(:request_backup).with(['postgresql', 'mongodb'])
      invoke(@backup, :create)
    end

    it "should display information about request backup" do
      @app.stub(:request_backup)
      $stdout.should_receive(:puts).with(green "Backup requested. It can take up to several minutes for " +
          "the backup process to finish.")
      invoke(@backup, :create)
    end

    it "should display information about missing kind or Cloudfile" do
      @cloudfile.stub(:present?).and_return(false)
      $stdout.should_receive(:puts).with(red "Cloudfile must be present in current working directory or specify database kind with:")
      $stdout.should_receive(:puts).with(red "`shelly backup create DB_KIND`")

      @backup.options = {:cloud => "foo-production"}
      lambda { invoke(@backup, :create) }.should raise_error(SystemExit)
    end
  end

  describe "restore" do
    before do
      @client.stub(:database_backup).and_return({"filename" => "better.tar.gz", "size" => 12345, "kind" => "postgresql"})
      @client.stub(:restore_backup).and_return({"filename" => "better.tar.gz", "size" => 12345, "kind" => "postgresql"})
      $stdout.stub(:puts)
      $stdout.stub(:print)
    end

    it "should ensure user has logged in" do
      hooks(@backup, :restore).should include(:logged_in?)
    end

    # multiple_clouds is tested in main_spec.rb in describe "#start" block
    it "should ensure multiple_clouds check" do
      @client.stub(:restore_backup)
      @backup.should_receive(:multiple_clouds).and_return(@app)
      fake_stdin(["yes"]) do
        invoke(@backup, :restore, "better.tar.gz")
      end
    end

    it "should restore database" do
      $stdout.should_receive(:puts).with("You are about to restore postgresql database for cloud foo-staging to state from better.tar.gz")
      $stdout.should_receive(:print).with("I want to restore the database (yes/no): ")
      $stdout.should_receive(:puts).with("\n")
      @client.stub(:restore_backup).with("todo-list-test","better.tar.gz")
      $stdout.should_receive(:puts).with("\n")
      $stdout.should_receive(:puts).with(green "Restore has been scheduled. Wait a few minutes till database is restored.")

      fake_stdin(["yes"]) do
        invoke(@backup, :restore, "better.tar.gz")
      end
    end

    context "when answering no" do
      it "should cancel restore database" do
        $stdout.should_receive(:puts).with("You are about to restore postgresql database for cloud foo-staging to state from better.tar.gz")
        $stdout.should_receive(:print).with("I want to restore the database (yes/no): ")
        $stdout.should_receive(:puts).with("\n")
        $stdout.should_receive(:puts).with(red "Canceled")

        lambda {
          fake_stdin(["no"]) do
            invoke(@backup, :restore, "better.tar.gz")
          end
        }.should raise_error(SystemExit)
      end
    end

    context "on backup not found" do
      it "should display error message" do
        response = {"resource" => "backup"}
        exception = Shelly::Client::NotFoundException.new(response)
        @client.stub(:database_backup).and_raise(exception)
        $stdout.should_receive(:puts).with(red "Backup not found")
        $stdout.should_receive(:puts).with("You can list available backups with `shelly backup list` command")
        invoke(@backup, :restore, "better.tar.gz")
      end
    end
  end

  describe "#import" do
    before do
      FileUtils.touch("dump.sql")
      @app.stub(:upload_database => {"server" => "app1"}, :ssh => nil)
      @app.stub(:import_database)
      @backup.stub(:system)
      $stdout.stub(:puts)
      $stdout.stub(:print)
      Time.stub_chain(:now, :to_i => 1370879705)
    end

    it "should ensure user has logged in" do
      hooks(@backup, :import).should include(:logged_in?)
    end

    it "should compress file" do
      @backup.should_receive(:system).with("tar -cjf dump.sql-1370879705.tar.bz2 dump.sql")
      $stdout.should_receive(:puts).with(green "Running: tar -cjf dump.sql-1370879705.tar.bz2 dump.sql")
      fake_stdin(["yes"]) do
        invoke(@backup, :import, "postgresql", "dump.sql")
      end
    end

    it "should upload compressed file" do
      @app.should_receive(:upload_database).with("dump.sql-1370879705.tar.bz2")
      $stdout.should_receive(:puts).with(green "Uploading dump.sql-1370879705.tar.bz2")
      fake_stdin(["yes"]) do
        invoke(@backup, :import, "postgresql", "dump.sql")
      end
    end

    it "should import given database from uploaded file" do
      @app.unstub(:import_database)
      @app.should_receive(:ssh_with_db_server).with(:command => "import_database postgresql dump.sql-1370879705.tar.bz2",
        :server => "app1")
      $stdout.should_receive(:puts).with(green "Importing database")
      fake_stdin(["yes"]) do
        invoke(@backup, :import, "postgresql", "dump.sql")
      end
    end

    context "on answering no" do
      it "should cancel database import" do
        $stdout.should_receive(:puts).with(yellow "You are about to import postgresql database for cloud foo-staging to state from file dump.sql")
        $stdout.should_receive(:print).with("I want to import the database from dump (yes/no): ")
        $stdout.should_receive(:puts).with(red "Canceled")
        lambda {
          fake_stdin(["no"]) do
            invoke(@backup, :import, "postgresql", "dump.sql")
          end
        }.should raise_error(SystemExit)
      end
    end

    context "file doesn't exist" do
      it "should exit with error" do
        FileUtils.rm("dump.sql")
        $stdout.should_receive(:puts).with(red "File dump.sql doesn't exist")
        lambda {
          fake_stdin(["yes"]) do
            invoke(@backup, :import, "postgresql", "dump.sql")
          end
        }.should raise_error(SystemExit)
      end
    end

    context "file doesn't exist" do
      it "should exit with error" do
        $stdout.should_receive(:puts).with(red "Kind is invalid. You can" \
          " import backup of: postgresql, mysql, mongodb")
        lambda {
          invoke(@backup, :import, "wrong_kind", "dump.sql")
        }.should raise_error(SystemExit)
      end
    end

    context "with --reset option" do
      it "should reset database first" do
        @app.unstub(:import_database)
        @backup.options = {:cloud => "foo-staging", :reset => true}
        @app.should_receive(:reset_database).with("postgresql")
        @app.should_receive(:ssh_with_db_server).with(
          :command => "import_database postgresql dump.sql-1370879705.tar.bz2",
          :server => "app1")
        $stdout.should_receive(:puts).with(green "Importing database")
        fake_stdin(["yes"]) do
          invoke(@backup, :import, "postgresql", "dump.sql")
        end
      end
    end
  end
end
