# Packages -- Arch stub for yast-packager's installation package proposal.
# Only IscsiClient touches it (addAdditionalPackage / vnc_packages), and only
# in installer mode. Nothing is ever selected for installation on Arch.
require "yast"
module Yast
  class PackagesClass < Module
    def main
      textdomain "packager"
      @additional_packages = []
    end
    def addAdditionalPackage(name) = (@additional_packages |= [name.to_s]; nil)
    def vnc_packages = []
    def remote_x11_packages = []
    def ssh_packages = []
    def braille_packages = []
    def modePackages = []
    def Init(*) = true
    def Proposal(*) = {}
    attr_reader :additional_packages
  end
  Packages = PackagesClass.new
  Packages.main
end
