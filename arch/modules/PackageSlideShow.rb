# PackageSlideShow -- Arch stub for yast-packager's installation slide show.
# The Language client imports it (installer-time package progress) but calls
# nothing outside the installer; on Arch no packages are ever installed by YaST.
require "yast"
module Yast
  class PackageSlideShowClass < Module
    def main = textdomain("packager")
    def InitPkgData(*) = nil
    def SetLanguage(*) = nil
    def SetInstalledPkgCount(*) = nil
    def GetPackageSummary(*) = {}
    def UpdateAllCdProgress(*) = nil
    def SlideDisplayStart(*) = nil
    def SlideDisplayDone(*) = nil
    def DisplayStart(*) = nil
    def DisplayEnd(*) = nil
    def PkgInstallStart(*) = nil
    def PkgInstallDone(*) = nil
    def DoneProvide(*) = nil
    def ProgressDeltaApply(*) = nil
    def ProgressDeltaDownload(*) = nil
    def ProgressDownload(*) = nil
    def StartPackage(*) = nil
    def DonePackage(*) = nil
    def method_missing(_n, *_a) = nil
    def respond_to_missing?(*) = true
  end
  PackageSlideShow = PackageSlideShowClass.new
  PackageSlideShow.main
end
