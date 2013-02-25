require "open3"

def use_fake_warden(root_dir)
  server = FakeWardenServer.new(root_dir)
  EM.const_set("Warden", EM::FakeWarden)
  EM.stub(:connect_unix_domain).with(anything, EM::FakeWarden::Client::Connection) do |socket, klass|
    klass.new(socket, server)
  end
end

class FakeWardenServer
  def initialize(root_dir)
    @root_dir = root_dir
    @handle_to_root_dir_map = {}
  end

  def handle_CreateRequest(r)
    handle = SecureRandom.hex(4)
    dir = Dir.mktmpdir(nil, @root_dir)
    initialize_container_dir(dir)
    r.bind_mounts.each { |mount| create_fake_bind_mount(mount, dir) }
    map_dir(handle, dir)
    ::Warden::Protocol::CreateResponse.new(:handle => handle)
  end

  def handle_InfoRequest(r)
    ::Warden::Protocol::InfoResponse.new(:container_path => get_dir(r.handle))
  end

  def handle_RunRequest(r)
    out, err, exit = run_command_in_fake_container(r.script, get_dir(r.handle))
    ::Warden::Protocol::RunResponse.new(:stdout => out, :stderr => err, :exit_status => exit.exitstatus)
  end

  def handle_CopyOutRequest(r)
    container_root = get_dir(r.handle)
    src_path = File.join(container_root, r.src_path)
    dst_path = r.dst_path
    FileUtils.cp_r(src_path, dst_path)
    ::Warden::Protocol::CopyOutResponse.new()
  end

  def handle_DestroyRequest(r)
    dir = get_dir(r.handle)
    FileUtils.rm_rf(dir)
    unmap(r.handle)
    ::Warden::Protocol::DestroyResponse.new()
  end

  private

  # Replace references to the root directory with references to the container's root
  FILE_PATH_PATTERN = %r{(\s+|=)(/[(?:var)(?:tmp)(?:bin)(?:usr)(?:Users)]\S+)}

  def run_command_in_fake_container(cmd, container_root)
    cmd.gsub!(FILE_PATH_PATTERN, '\1' + container_root + '\2')
    Open3.capture3({}, "cd #{container_root} && #{cmd}", :unsetenv_others => true)
  end

  def initialize_container_dir(dir)
    FileUtils.mkdir_p("#{dir}/tmp/unstaged")
    FileUtils.mkdir_p("#{dir}/usr/bin")
    File.symlink(`which ruby`.strip, "#{dir}/usr/bin/ruby")
  end

  def create_fake_bind_mount(mount, container_dir)
    host_path = mount.src_path
    container_path = File.join(container_dir, mount.dst_path)
    FileUtils.mkdir_p(File.dirname(container_path))
    File.symlink(host_path, container_path)
  end

  def map_dir(handle, root_dir)
    @handle_to_root_dir_map[handle] = root_dir
  end

  def get_dir(handle)
    @handle_to_root_dir_map[handle]
  end

  def unmap(handle)
    @handle_to_root_dir_map.delete(handle)
  end
end

module EM
  module FakeWarden
    module Client
      Error = ::EM::Warden::Client::Error

      class Connection
        def initialize(socket, server)
          @socket = socket
          @server = server
        end

        def call(request)
          request_type = request.class.name.split("::").last
          response = @server.send("handle_#{request_type}", request)
          yield(OpenStruct.new(:get => response))
        end

        def connected?
          true
        end

        def on(event_name)
          if event_name == :connected
            yield
          end
        end
      end
    end
  end
end

