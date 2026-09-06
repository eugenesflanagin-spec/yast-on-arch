# Pkg -- Arch Linux stand-in for yast2-pkg-bindings (libzypp/RPM).
#
# On openSUSE "Pkg" is a C++ namespace bound to libzypp. It cannot exist on
# Arch. Many otherwise-useful modules (Language, Timezone, Security, Kernel,
# Product, ...) still `import "Pkg"` because their *installer* code paths use
# it, so without this file every one of them dies at import time with
#   "component cannot import namespace 'Pkg'".
#
# This module makes the import succeed. Query-type calls are answered from
# pacman where that is meaningful (installed? version compare?); everything
# that would touch repositories, the solver or a transaction is a logged no-op
# returning a type-correct empty/false value. Nothing here ever installs or
# removes a package.
#
# Part of yast-on-arch: https://github.com/eugenesflanagin-spec/yast-on-arch
require "yast"

module Yast
  class PkgClass < Module
    include Yast::Logger

    def main
      textdomain "base"
      @last_error = ""
      @locale = ENV["LANG"].to_s.sub(/\..*/, "")
      @locale = "en_US" if @locale.empty? || @locale == "C"
      @additional_locales = []
      @solver_flags = {}
      log.info "Pkg: Arch Linux stub loaded (pacman-backed queries, no-op transactions)"
    end

    # ------------------------------------------------------------ pacman-backed
    def PkgInstalled(name)   = pacman_installed?(name)
    def IsProvided(name)     = pacman_installed?(name) || pacman_provided?(name)
    def IsAvailable(name)    = pacman_available?(name)
    def PkgAvailable(name)   = pacman_available?(name)
    def IsSelected(_name)    = false
    def PkgQueryProvides(cap)
      out = `pacman -Qq 2>/dev/null`.split
      out.include?(cap) ? [[cap, :CAND, :INST]] : []
    end
    # returns -1 / 0 / 1 like libzypp
    def CompareVersions(a, b)
      r = `vercmp #{shell(a)} #{shell(b)} 2>/dev/null`.strip
      r.empty? ? 0 : r.to_i
    end
    def GetPackages(_which = :installed, names_only = true)
      list = `pacman -Qq 2>/dev/null`.split
      names_only ? list : list.map { |n| [n] }
    end

    # -------------------------------------------------------------- locales
    def GetTextLocale            = @locale
    def SetTextLocale(l)         = (@locale = l.to_s; true)
    def SetLocale(l)             = SetTextLocale(l)
    def SetPackageLocale(l)      = SetTextLocale(l)
    def GetAdditionalLocales     = @additional_locales
    def SetAdditionalLocales(ls) = (@additional_locales = Array(ls); true)

    # ------------------------------------------------ target / sources / solver
    def TargetInit(_root = "/", _new = false) = true
    def TargetInitialize(_root = "/")         = true
    def TargetLoad                            = true
    def TargetFinish                          = true
    def TargetGetDU                           = {}
    def TargetProducts                        = []
    def Connect                               = true
    def LastError                             = @last_error
    def LastErrorId                           = ""
    def SourceStartManager(_e = true)         = true
    def SourceStartCache(_e = true)           = []
    def SourceRestore                         = true
    def SourceLoad                            = true
    def SourceSaveAll                         = true
    def SourceReleaseAll                      = true
    def SourceGetCurrent(_e = true)           = []
    def SourceGeneralData(_id)                = {}
    def SourceSetEnabled(_id, _e)             = true
    def SourceDelete(_id)                     = true
    def SourceRefreshNow(_id)                 = true
    def SourceForceRefreshNow(_id)            = true
    def SourceChangeUrl(_id, _url)            = true
    def SourceProvideFile(*_a)                = nil
    def SourceProvideOptionalFile(*_a)        = nil
    def SourceProvideDigestedFile(*_a)        = nil
    def SkipRefresh                           = nil
    def RepositoryAdd(_h)                     = -1
    def ServiceAliases                        = []
    def ServiceGet(_a)                        = {}
    def ServiceRefresh(_a)                    = true
    def ExpandedUrl(u)                        = u
    def GetSolverFlags                        = @solver_flags
    def SetSolverFlags(h)                     = (@solver_flags = h || {}; true)
    def PkgSolve(_filter = true)              = true
    def PkgSolveCheckTargetOnly               = true
    def PkgMediaSizes                         = []
    def PkgMediaCount                         = []
    def Resolvables(*_a)                      = []
    def ResolvableProperties(*_a)             = []
    def AnyResolvable(*_a)                    = false
    def IsAnyResolvable(*_a)                  = false
    def PkgGetLicensesToConfirm(*_a)          = []
    def PkgMarkLicenseConfirmed(*_a)          = true
    def PrdNeedToAcceptLicense(*_a)           = false
    def PrdGetLicenseToConfirm(*_a)           = ""
    def PrdLicenseLocales(*_a)                = []
    def PrdMarkLicenseConfirmed(*_a)          = true
    def PrdMarkLicenseNotConfirmed(*_a)       = true
    def PkgNeutral(_n)                        = true
    def ResolvableNeutral(*_a)                = true

    # ---------------------------------------------- transactions: refused, logged
    def PkgInstall(n)        = refuse("PkgInstall #{n}")
    def PkgDelete(n)         = refuse("PkgDelete #{n}")
    def PkgTaboo(n)          = refuse("PkgTaboo #{n}")
    def ResolvableInstall(*a)= refuse("ResolvableInstall #{a.inspect}")
    def ResolvableRemove(*a) = refuse("ResolvableRemove #{a.inspect}")
    def ProvidePackage(*a)   = refuse("ProvidePackage #{a.inspect}")
    # libzypp returns [successful, failed, remaining, srcremaining]
    def PkgCommit(_media = 0) = [[], [], [], []]
    def Commit(_cfg = {})     = [[], [], [], []]

    # Every Pkg.Callback* registration is a no-op here.
    def method_missing(name, *args, &blk)
      return nil if name.to_s.start_with?("Callback")
      Builtins.y2warning("Pkg (Arch stub): unimplemented %1(%2) -> nil", name.to_s, args.map(&:inspect).join(", "))
      nil
    end
    def respond_to_missing?(name, _priv = false) = name.to_s.start_with?("Callback") || super

    private

    def shell(s) = "'" + s.to_s.gsub("'", "'\\\\''") + "'"
    def pacman_installed?(name) = system("pacman", "-Qq", name.to_s, out: File::NULL, err: File::NULL)
    def pacman_provided?(name)  = system("pacman", "-Qq", "--satisfies", name.to_s, out: File::NULL, err: File::NULL) rescue false
    def pacman_available?(name) = system("pacman", "-Si", name.to_s, out: File::NULL, err: File::NULL)
    def refuse(what)
      @last_error = "package transactions are not supported by yast-on-arch (#{what}); use Octopi/pacman"
      log.warn "Pkg (Arch stub): refused #{what}"
      false
    end
  end

  Pkg = PkgClass.new
  Pkg.main
end
