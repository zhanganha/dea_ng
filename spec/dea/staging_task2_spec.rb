# coding: UTF-8

require "spec_helper"
require "dea/staging_task"
require "dea/directory_server_v2"
require "em-http"

describe Dea::StagingTask do
  let(:base_dir) { Dir.mktmpdir }
  let(:cache_dir) { Dir.mktmpdir }
  let(:insight_dir) { Dir.mktmpdir("insight") }
  let(:insight_agent_file) do
    file_path = File.join(insight_dir, "insight_agent.file")
    FileUtils.touch(file_path)
    file_path
  end

  let(:config) do
    {
      "base_dir" => base_dir,
      "dea_ruby" => '/usr/bin/ruby',
      "bind_mounts" => [],
      "directory_server" => {
        "file_api_port" => 1234
      },
      "staging" => {
        "environment" => {},
        "platform_config" => {"insight_agent" => insight_agent_file }
      },
    }
  end

  let(:bootstrap) { mock(:bootstrap, :config => config) }
  let(:dir_server) { Dea::DirectoryServerV2.new("domain", 1234, config) }
  let(:download_uri) { "http://ccng.somwhere/app-download" }
  let(:upload_uri) { "http://ccng.somwhere/app-upload" }
  let(:override) do
    {
      "download_uri" => download_uri,
      "upload_uri" => upload_uri,
    }
  end

  let(:attributes) do
    valid_staging_attributes.merge(override)
  end

  let(:logger) do
    mock("logger").tap do |l|
      %w(debug debug2 info warn).each { |m| l.stub(m) }
    end
  end

  let(:task) { Dea::StagingTask.new(bootstrap, dir_server, attributes) }

  before do
    FileUtils.mkdir_p(File.join(config["base_dir"], "staging"))
  end

  after do
    FileUtils.rm_rf(base_dir)
    FileUtils.rm_rf(cache_dir)
    FileUtils.rm_rf(insight_dir)
  end

  def mock_download(expected_uri, filename, fixture_path)
    Download.should_receive(:new).with(expected_uri, anything) do |uri, dir|
      fake_download = mock(:download)
      full_path = File.join(dir, filename)
      FileUtils.cp_r(fixture_path, full_path)
      fake_download.stub(:download!).and_yield(nil, full_path)
      fake_download
    end
  end

  def mock_upload(expected_uri, &block)
    Upload.should_receive(:new).with(anything, expected_uri) do |uploaded_path|
      block.call(uploaded_path) if block
      fake_upload = mock(:upload)
      fake_upload.stub(:upload!).and_yield(nil)
      fake_upload
    end
  end

  def extract_app(app_path)
    `tar xzf #{app_path}`
  end

  describe "#start" do
    subject { task.start }

    before do
      use_fake_warden Dir.mktmpdir("warden_depot")
      mock_download(download_uri, "some-path.tgz", File.expand_path("../../fixtures/app.zip", __FILE__))
    end

    it "uploads the correct staged upp" do
      mock_upload(upload_uri) do |file_path|
        File.exists?(file_path).should be_true
        Dir.chdir(File.dirname(file_path)) do
          extract_app(file_path)
          puts "Entries: #{Dir.entries(".")}"
          puts File.read("./logs/staging_task.log")
        end
      end
      subject
    end

    it "creates a config file in the right place" do
      mock_upload(upload_uri)
      subject
      # staging_dir = File.join(base_dir, "staging")
      # puts "staging_dir: #{staging_dir}"
      # workspace_dir = Dir.glob(File.join(staging_dir, "*")).first
      # File.exists?(File.join(workspace_dir, "plugin_config")).should be_true
    end
  end
end
