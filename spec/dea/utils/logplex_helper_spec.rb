require 'spec_helper'
require 'dea/utils/logplex_helper'

describe LogplexHelper do
  let(:log_port) { 9876 }
  let(:api_port) { 2001 }
  let(:test_config) {
    {
      :host => "not.for.real",
      :api_port => api_port,
      :log_port => log_port
    }
  }

  let(:subject) { LogplexHelper.new(test_config) }

  describe "singleton-ness" do
    describe '.get' do
      it 'creates a singleton' do
        logplex_helper = LogplexHelper.get()
        logplex_helper.should be_a(LogplexHelper)

        logplex_helper.should === LogplexHelper.get()
      end
    end
  end

  describe "configuration" do
    its(:host) { should == "not.for.real" }
    its(:api_port) { should == 2001 }
    its(:log_port) { should == 9876 }
  end

  describe "#format_message" do
    it "correctly formats a simple log message" do
      subject.format_message("log this!").should == <<-MESSAGE

      MESSAGE
    end
  end

  describe '#log_message' do
    let(:log_port) { 9876 }
    let(:api_port) { 8001 }

    around do |example|
      em { example.call }
    end

    it 'creates a new channel' do
      start_http_server(api_port) do |connection, data|
        response_json = {:channel_id => 1,
          :tokens => {:app => "deadbeef"}}
        reply(Yajl::Encoder.encode(response_json), connection)
        data.lines.first.should =~ %r|/channels|
        data.lines.first.should =~ /POST/
      end

      subject.log_message("sup") do |status|
        done
      end
    end

    it 'posts the given message to the channel' do
      log_post_request_made = false

      start_http_server(8001) do |connection, data|
        if data =~ %r|POST /channels HTTP/1\.1|
          response_json = {:channel_id => 1,
            :tokens => {:app => "deadbeef"}}
          reply(Yajl::Encoder.encode(response_json), connection)
        end
      end

      start_http_server(8601) do |connection, data|
        log_post_request_made = true
        data.should == <<-HTTP
POST /logs HTTP/1.1
Content-Type: application/logplex-1"
Content-Length: 7

5 Logs!
        HTTP
        reply("OK", connection)
      end

      subject.log_message("sup") do
        done
        fail("no log message posted") unless log_post_request_made
      end
    end
  end

  describe "asdf" do
    around do |example|
      em { example.call }
    end

    describe "#send_log" do
      xit "posts the given message to the log_server" do
        start_http_server(log_port) do |connection, data|
          data.should == <<-HTTP
POST /logs HTTP/1.1
Content-Type: application/logplex-1"
Content-Length: 7

5 Logs!
          HTTP
          reply("Logged!", connection)
        end

        subject.send(:send_log, "Logs!") do
          done
        end
      end

      context "success" do
        it "executes the given callback upon success"
      end

      context "failure" do
        it "executes the given callback upon error"
      end

=begin
  LoplexHelper.send(:send_log, "my message") do |error|
    if error
      puts "log could not be posted: #{error}"
      retry logic
    else
      puts "logged successfully"
    end
  end

  blah.blah
    on_success:
    on_failure:
=end
    end
  end

  def reply(body, connection)
    connection.send_data("HTTP/1.1 200 OK\r\n")
    connection.send_data("Content-Length: #{body.length}\r\n")
    connection.send_data("\r\n")
    connection.send_data(body)
    connection.send_data("\r\n")
  end
end
