# SLPAPI -- Arch stub. The real one (yast-slp) discovers services with OpenSLP;
# nothing on this box announces via SLP, so every query finds nothing.
require "yast"
module Yast
  class SLPAPIClass < Module
    def main = textdomain("slp")
    def FindSrvs(*)      = []
    def FindSrvTypes(*)  = []
    def FindAttrs(*)     = []
    def GetUnicastAttrMap(*) = {}
    def RegService(*)    = false
    def DeRegService(*)  = false
    def UnicastFindSrvs(*) = []
    def MatchType(*)     = false
    def AttrString(*)    = ""
  end
  SLPAPI = SLPAPIClass.new
  SLPAPI.main
end
