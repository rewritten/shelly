require "spec_helper"
require "shelly/cli/account"

describe Shelly::CLI::Account do
  before do
    FileUtils.stub(:chmod)
    @client = mock
    @account = Shelly::CLI::Account.new
    Shelly::Client.stub(:new).and_return(@client)
    $stdout.stub(:puts)
    $stdout.stub(:print)
  end

  describe "#register" do
    before do
      Shelly::User.stub(:guess_email).and_return("")
      @client.stub(:register_user)
      @key_path = File.expand_path("~/.ssh/id_rsa.pub")
    end

    it "should ask for email, password and password confirmation" do
      $stdout.should_receive(:print).with("Email: ")
      $stdout.should_receive(:print).with("Password: ")
      $stdout.should_receive(:print).with("Password confirmation: ")
      fake_stdin(["better@example.com", "secret", "secret"]) do
        @account.register
      end
    end

    it "should suggest email and use it if user enters blank email" do
      Shelly::User.stub(:guess_email).and_return("kate@example.com")
      $stdout.should_receive(:print).with("Email (kate@example.com - default): ")
      @client.should_receive(:register_user).with("kate@example.com", "secret", nil)
      fake_stdin(["", "secret", "secret"]) do
        @account.register
      end
    end

    it "should use email provided by user" do
      @client.should_receive(:register_user).with("better@example.com", "secret", nil)
      fake_stdin(["better@example.com", "secret", "secret"]) do
        @account.register
      end
    end

    context "when user enters blank email" do
      it "should show error message and exit with 1" do
        Shelly::User.stub(:guess_email).and_return("")
        $stdout.should_receive(:puts).with("Email can't be blank, please try again")
        lambda {
          fake_stdin(["", "bob@example.com", "only-pass", "only-pass"]) do
            @account.register
          end
        }.should raise_error(SystemExit)
      end
    end

    context "when user enters blank password" do
      it "should ask for it again" do
        $stdout.should_receive(:puts).with("Password can't be blank")
        fake_stdin(["better@example.com", "", "", "secret", "secret"]) do
          @account.register
        end
      end
    end

    context "when user enters password and password confirmation which don't match each other" do
      it "should ask for them again" do
        $stdout.should_receive(:puts).with("Password and password confirmation don't match, please type them again")
        fake_stdin(["better@example.com", "secret", "sec-TYPO-ret", "secret", "secret"]) do
          @account.register
        end
      end
    end

    context "public SSH key exists" do
      it "should register with the public SSH key" do
        FileUtils.mkdir_p("~/.ssh")
        File.open(@key_path, "w") { |f| f << "key" }
        $stdout.should_receive(:puts).with("Uploading your public SSH key from #{@key_path}")
        fake_stdin(["kate@example.com", "secret", "secret"]) do
          @account.register
        end
      end
    end

    context "public SSH key doesn't exist" do
      it "should register user without the public SSH key" do
        $stdout.should_not_receive(:puts).with("Uploading your public SSH key from #{@key_path}")
        fake_stdin(["kate@example.com", "secret", "secret"]) do
          @account.register
        end
      end
    end

    context "on successful registration" do
      it "should display message about registration and email address confirmation" do
        @client.stub(:register_user).and_return(true)
        $stdout.should_receive(:puts).with("Successfully registered!")
        $stdout.should_receive(:puts).with("Check you mailbox for email address confirmation")
        fake_stdin(["kate@example.com", "pass", "pass"]) do
          @account.register
        end
      end
    end

    context "on unsuccessful registration" do
      it "should display errors and exit with 1" do
        response = {"message" => "Validation Failed", "errors" => [["email", "has been already taken"]]}
        exception = Shelly::Client::APIError.new(response)
        @client.stub(:register_user).and_raise(exception)
        $stdout.should_receive(:puts).with("email has been already taken")
        lambda {
          fake_stdin(["kate@example.com", "pass", "pass"]) do
            @account.register
          end
        }.should raise_error(SystemExit)
      end
    end
  end
end