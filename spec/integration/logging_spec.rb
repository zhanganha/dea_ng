require "spec_helper"
require "timeout"
require "digest/sha1"
require "patron"

describe "Logging", :type => :integration, :requires_erlang => true, :requires_warden => true do
  describe "staging an app" do
    let(:nats) { NatsHelper.new }
    let(:unstaged_url) { "http://localhost:9999/unstaged/sinatra" }
    let(:staged_url) { "http://localhost:9999/staged/sinatra" }
    let(:dea_hostname) { `hostname -I`.split(" ")[0] }
    let(:buildpack_url) { "http://#{dea_hostname}:9999/buildpacks/with_start_cmd/succeed_to_detect/.git" }
    let(:logplex_api_session) do
      http = Patron::Session.new
      http.headers["Authorization"] = "Basic auth_key"
      http.base_url = "http://localhost:8001"
      http
    end

    it 'can see a healthy log server' do
      expect(logplex_api_session.get("/healthcheck").body).to include("OK")
    end

    it "staging logs its progress" do
      setup_fake_buildpack

      channel_creation_response = logplex_api_session.post('/channels', {'tokens' => ['staging'], 'name' => "my-channel"}.to_json)
      parsed_response = JSON.parse(channel_creation_response.body)
      channel_id = parsed_response['channel_id']
      staging_token = parsed_response['tokens']['staging']

      #`curl -v \
      #-H "Content-Type: application/logplex-1" \
      #-H "Content-Length: 88" \
      #-d "85 <134>1 2012-12-10T03:00:48Z+00:00 erlang space-id some-app-id.stager - Hello from DEA" \
      #http://token:#{staging_token}@#{dea_hostname}:8601/logs`

      response = nats.request("staging", {
        "async" => false,
        "app_id" => "some-app-id",
        "properties" => {
          "buildpack" => buildpack_url,
          "log_token" => staging_token
        },
        "download_uri" => unstaged_url,
        "upload_uri" => staged_url
      })

      session_token_response = logplex_api_session.post("/v2/sessions", {:channel_id => channel_id.to_s }.to_json)
      session_path = JSON.parse(session_token_response.body)['url']

      log_query_response = logplex_api_session.get("#{session_path}?srv=1")
      log_query_response.body.should include("stag")
    end

    def setup_fake_buildpack
      Dir.chdir("spec/fixtures/fake_buildpacks/with_start_cmd/succeed_to_detect") do
        `rm -rf .git`
        `git init`
        `git add . && git add -A`
        `git commit -am "fake commit"`
        `git update-server-info`
      end
    end
  end
end
