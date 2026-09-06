# Pkg -- Arch Linux stand-in for yast2-pkg-bindings (libzypp/RPM).
#
# On openSUSE "Pkg" is a C++ namespace bound to libzypp. It cannot exist on
# Arch. Many otherwise-useful modules (Language, Timezone, Security, Kernel,
# Product, ...) still `import "Pkg"` because their *installer* code paths use
# it, so without this file every one of them dies at import time with
#   "component cannot import namespace 'Pkg'".
#
# This module makes the import succeed. Query-type calls are answered from
# pacman where that is meaningful (installed? version compare?); repositories
# and the solver are typed no-ops. Nothing here ever runs pacman -S/-R: when a
# module needs a package that is missing, PkgCommit shows the exact pacman
# command for the user to run and reports the install as failed.
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
      @to_install = []
      log.info "Pkg: Arch Linux stub loaded (pacman-backed queries, no-op transactions)"
    end

    # openSUSE package names the modules ask for -> Arch package(s). A nil
    # value means "no Arch equivalent" (reported as not available). Names
    # not listed are tried as-is (pacman -T honours provides=).
    NAME_MAP = {
      "nfs-kernel-server" => "nfs-utils", "nfs-client" => "nfs-utils",
      "samba-client" => "smbclient", "samba-winbind" => "samba", "samba-pdb" => "samba",
      "iscsiuio" => "open-iscsi", "NetworkManager" => "networkmanager",
      "strongswan-ipsec" => "strongswan", "setxkbmap" => "xorg-setxkbmap",
      "tftp" => "tftp-hpa", "apparmor-parser" => "apparmor", "apparmor-utils" => "apparmor",
      "apparmor-profiles" => "apparmor", "dhcp-server" => "dhcp", "krb5-client" => "krb5",
      "krb5-plugin-preauth-pkinit-nss" => "krb5", "qemu" => "qemu-base", "kvm" => "qemu-base",
      "openldap2-client" => "openldap", "openldap2" => "openldap", "ypbind" => "ypbind-mt",
      # Boot Loader's "prepare system" list. Arch's single grub package covers every
      # firmware target; shim/mokutil (openSUSE Secure Boot) have no repo package and
      # Arch GRUB boots EFI without them, so they are satisfied by grub as well.
      "grub2" => "grub", "grub2-x86_64-efi" => "grub", "grub2-i386-pc" => "grub",
      "grub2-arm64-efi" => "grub", "shim" => "grub", "mokutil" => "grub",
      "grub2-branding-openSUSE" => nil, "perl-Bootloader" => nil,
      "yp-tools" => "yp-tools", "nscd" => nil, "wicked" => nil, "ndiswrapper" => nil, "xen" => nil,
    }.freeze
    # packages that are "the system itself" here -- always considered installed
    VIRTUAL = /\A(yast2|kernel|patterns|libzypp|zypper|rpm)(-|\z)/

    # ------------------------------------------------------------ pacman-backed
    def PkgInstalled(name)   = virtual?(name) || pacman_installed?(name)
    def IsProvided(name)     = PkgInstalled(name)
    def IsAvailable(name)    = virtual?(name) || pacman_available?(name)
    def PkgAvailable(name)   = IsAvailable(name)
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
    def SourceGetCurrent(_e = true)           = [0]
    def SourceGeneralData(_id)
      { "alias" => "pacman", "name" => "pacman sync database", "enabled" => true,
        "autorefresh" => false, "url" => "pacman:///", "product_dir" => "/", "type" => "pacman" }
    end
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
    def PkgGetLicensesToConfirm(*_a)          = []
    def PkgMarkLicenseConfirmed(*_a)          = true
    def PrdNeedToAcceptLicense(*_a)           = false
    def PrdGetLicenseToConfirm(*_a)           = ""
    def PrdLicenseLocales(*_a)                = []
    def PrdMarkLicenseConfirmed(*_a)          = true
    def PrdMarkLicenseNotConfirmed(*_a)       = true
    def PkgNeutral(_n)                        = true
    def ResolvableNeutral(*_a)                = true

    # ---------------------------- transactions: queued, shown, never executed
    # A module asks "package X is missing, install it?"; YaST then calls
    # PkgInstall(x) and PkgCommit. We resolve the Arch name(s) so the hint is
    # correct, and PkgCommit hands the pacman command to the user instead of
    # running it. Removals are refused outright.
    def PkgInstall(n)
      arch = arch_names(n)
      if arch.empty?
        @last_error = "no Arch package corresponds to '#{n}'"
        log.warn "Pkg (Arch stub): #{@last_error}"
        return false
      end
      @to_install |= arch
      log.info "Pkg (Arch stub): queued #{n} -> #{arch.join(' ')}"
      true
    end
    def PkgDelete(n)         = refuse("PkgDelete #{n}")
    def PkgTaboo(n)          = refuse("PkgTaboo #{n}")
    def ResolvableInstall(name, kind = :package, *_a) = kind == :package ? PkgInstall(name) : refuse("ResolvableInstall #{kind} #{name}")
    def ResolvableRemove(*a) = refuse("ResolvableRemove #{a.inspect}")
    def ProvidePackage(*a)   = refuse("ProvidePackage #{a.inspect}")
    def IsAnyResolvable(_kind = :package, status = :to_install, *_a) = status == :to_install && !@to_install.empty?
    def AnyResolvable(*a)    = IsAnyResolvable(*a)
    # libzypp returns [successful, failed, remaining, srcremaining]
    def PkgCommit(_media = 0)
      pkgs = @to_install.dup
      @to_install = []
      return [[], [], [], []] if pkgs.empty?
      # NEVER executes pacman. Two unattended runs today showed that a YaST
      # "Install?" prompt can be answered by things other than a human (a
      # closed stdin in ncurses, a stray click), so this stand-in only tells
      # the user what to run and reports the packages as not installed.
      cmd = "sudo pacman -S --needed #{pkgs.join(' ')}"
      @last_error = "not installed automatically on Arch; run: #{cmd}"
      log.warn "Pkg (Arch stub): refusing to install #{pkgs.join(' ')}; user must run: #{cmd}"
      begin
        Yast.import "Mode"
        unless Mode.commandline
          Yast.import "Popup"
          Popup.LongText(
            "Packages needed by this module",
            "<p>YaST on Arch does not install packages by itself.</p>" \
            "<p>Install them in a terminal, then reopen the module:</p>" \
            "<pre>#{cmd}</pre>",
            60, 8
          )
        end
      rescue StandardError => e
        log.error "Pkg (Arch stub): could not show the install hint (#{e.message})"
      end
      [[], pkgs, [], []]
    end
    def Commit(_cfg = {})     = PkgCommit(0)

    # Every Pkg.Callback* registration is a no-op here.
    def method_missing(name, *args, &blk)
      return nil if name.to_s.start_with?("Callback")
      Builtins.y2warning("Pkg (Arch stub): unimplemented %1(%2) -> nil", name.to_s, args.map(&:inspect).join(", "))
      nil
    end
    def respond_to_missing?(name, _priv = false) = name.to_s.start_with?("Callback") || super

    private

    def shell(s) = "'" + s.to_s.gsub("'", "'\\\\''") + "'"
    def virtual?(name) = !!(name.to_s =~ VIRTUAL)
    def arch_names(name)
      n = name.to_s
      return [] if virtual?(n)
      NAME_MAP.key?(n) ? Array(NAME_MAP[n]).compact : [n]
    end
    # pacman -T: exit 0 when the dependency is satisfied (installed or provided)
    def pacman_installed?(name)
      arch = arch_names(name)
      !arch.empty? && arch.all? { |a| system("pacman", "-T", a, out: File::NULL, err: File::NULL) }
    end
    def pacman_available?(name)
      arch = arch_names(name)
      !arch.empty? && arch.all? { |a| system("pacman", "-Si", a, out: File::NULL, err: File::NULL) }
    end
    def refuse(what)
      @last_error = "package transactions are not supported by yast-on-arch (#{what}); use Octopi/pacman"
      log.warn "Pkg (Arch stub): refused #{what}"
      false
    end
  end

  Pkg = PkgClass.new
  Pkg.main
end
