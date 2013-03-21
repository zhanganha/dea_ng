class LogplexHelper
  attr_reader :host, :api_port, :log_port

  @@instance = nil

  def self.get(config = {})
    @@instance ||
      @@instance = LogplexHelper.new(config)
  end

  def initialize(logging_config)
    @host = logging_config[:host]
    @api_port = logging_config[:api_port]
    @log_port = logging_config[:log_port]
  end

  def log_message(message, &blk)
    request_channel do |status|
      send_log message, blk
    end
  end

  private

  def request_channel(&channel_provision_callback)
    http = EM::HttpRequest.new("http://#{host}:#{api_port}/channels").post()

    http.callback do
      #Yajl::Parser.parse(http.response)
      channel_provision_callback.call(:success) if channel_provision_callback
    end

    http.errback do
      channel_provision_callback.call(:error) if channel_provision_callback
    end
  end

  def send_log(message, &log_sending_callback)
    http = EM::HttpRequest.new("http://#{host}:#{log_port}/logs").post(
      :body => message
    )

=begin
    http.callback do
      log_sending_callback.call()
    end
    http.errback do
      log_sending_callback.call()
      raise :hell
    end
=end
  end
end
