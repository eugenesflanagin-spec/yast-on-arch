# InstURL -- Arch stub. The real one (yast-packager) turns linuxrc's install.inf
# into a repository URL; that only exists during an openSUSE installation.
require "yast"
module Yast
  class InstURLClass < Module
    def main = textdomain("packager")
    def installInf(_key = nil) = ""
    def installInf2Url(_extra = "") = ""
    def is_network(_url = "") = false
    def RewriteCDUrl(url) = url
  end
  InstURL = InstURLClass.new
  InstURL.main
end
