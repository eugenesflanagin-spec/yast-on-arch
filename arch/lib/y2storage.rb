# y2storage -- minimal Arch Linux shim for yast-storage-ng.
#
# The real Y2Storage is a large Ruby layer over libstorage-ng (C++ + SWIG),
# which is not ported. Outside the installer, the modules shipped by
# yast-on-arch only ask two things of it:
#   * "is the root filesystem on a network device?" (y2network)
#   * "is the root filesystem read-only?"           (y2security SELinux)
# and Timezone wants a disk analyzer to look for a Windows partition.
# All three are answered here from /proc/mounts and /proc/partitions.
#
# REMOVE THIS FILE (and lib/y2storage/) if the real yast-storage-ng is ever
# installed into the prefix -- it would shadow it.
#
# Part of yast-on-arch: https://github.com/eugenesflanagin-spec/yast-on-arch
require "y2storage/storage_manager"
