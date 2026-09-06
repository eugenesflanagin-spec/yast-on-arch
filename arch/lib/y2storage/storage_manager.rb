# See ../y2storage.rb -- Arch shim, not the real yast-storage-ng.
require "singleton"

module Y2Storage
  NETWORK_FS = %w[nfs nfs4 cifs smb3 ceph fuse.sshfs glusterfs].freeze

  # One mounted filesystem, read from /proc/mounts.
  class MountPoint
    attr_reader :path, :mount_options
    def initialize(path, options) = (@path = path; @mount_options = options)
    def read_only? = @mount_options.include?("ro")
  end

  class Filesystem
    attr_reader :device, :type, :mount_point
    def initialize(device, path, type, options)
      @device = device; @type = type
      @mount_point = MountPoint.new(path, options)
    end
    def root?        = mount_point.path == "/"
    def in_network?  = NETWORK_FS.include?(type)
    def mount_path   = mount_point.path
  end

  class Devicegraph
    def filesystems
      @filesystems ||= File.readlines("/proc/mounts").map do |l|
        dev, path, type, opts = l.split
        next if path.nil?
        path = path.gsub(/\\040/, " ")
        Filesystem.new(dev, path, type, opts.to_s.split(","))
      end.compact
    end
    # Longest mount-point prefix wins, like the real implementation.
    def filesystem_at(path)
      filesystems.select { |fs| path == fs.mount_path || path.start_with?(fs.mount_path.chomp("/") + "/") }
                 .max_by { |fs| fs.mount_path.length }
    end
    def filesystem_in_network?(path) = !!filesystem_at(path)&.in_network?
    def nfs_mounts = filesystems.select(&:in_network?)
    def disks = []
    def partitions = []
  end

  # Timezone.rb asks this for Windows partitions to guess a local-time RTC.
  class DiskAnalyzer
    def windows_partitions(*) = []
    def windows_system?(*)    = false
    def windows_systems(*)    = []
    def linux_partitions(*)   = []
  end

  class StorageManager
    include Singleton
    def probed  = (@graph ||= Devicegraph.new)
    def staging = probed
    def system  = probed
    def probed_disk_analyzer = (@analyzer ||= DiskAnalyzer.new)
    def probe   = true
    def commit(*) = false
    def self.instance = super
  end
end
