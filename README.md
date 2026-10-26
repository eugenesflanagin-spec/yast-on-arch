# yast-on-arch

**openSUSE's YaST, running on Arch Linux.**

YaST was retired upstream — openSUSE Leap 16 dropped graphical YaST entirely — and no
non-SUSE port has existed since [YaST4Debian](https://en.wikipedia.org/wiki/YaST) went dormant
around 2010. This repo makes it build and run on Arch.

**Version 0.3.0** — what changed: [CHANGELOG.md](CHANGELOG.md).
**New here? Read the [User Guide](docs/USER-GUIDE.md)**: install from a fresh Arch system,
starting modules from the menu, adding your own programs to the Control Center, what works and
what doesn't, safety, troubleshooting, uninstall.

It ships **patches and build scripts, not vendored code**. `bootstrap.sh` clones upstream
libyui/YaST at pinned commits, applies the Arch fixes, and installs into a self-contained
prefix (`~/libyui-port/prefix`). Outside that prefix it installs:

- **32 pacman packages** (`sudo pacman -S --needed`, already-installed ones are skipped):
  `cmake ninja boost qt5-base qt5-x11extras gtk3 ncurses gettext libxcrypt pkgconf git ruby ruby-rake bison
  flex libtool automake autoconf dejagnu docbook-xsl libxslt perl-xml-writer fdupes
  ruby-nokogiri ruby-augeas augeas libxml2 json-c swig perl-crypt-smbhash xorg-xhost doxygen`
  (`./bootstrap.sh --deps` prints the list without installing anything);
- **user-scope Ruby gems** (`gem install --user-install`): `fast_gettext` (<3.0), `cheetah`,
  `simpleidn`, `abstract_method`, `yast-rake`, `prime`, `cfa`, `cfa_grub2`, `ruby-dbus`;
- **four menu entries** in `~/.local/share/applications` (from `desktop/`, with the real
  launcher path filled in; an existing file of the same name that bootstrap didn't write is
  left alone; `YAST_NO_MENU_ENTRIES=1` skips them);
- **your own Control Center entries**, only if you add some with `yast add-app`, in
  `~/.local/share/yast-on-arch/applications` (see below);
- **one systemd drop-in**, `/etc/systemd/system/ypbind.service.d/50-yast-arch-args.conf`,
  only if `ypbind-mt` is installed (NIS client, see patch 19).

```bash
git clone https://github.com/eugenesflanagin-spec/yast-on-arch
cd yast-on-arch && ./bootstrap.sh

~/libyui-port/yast -r -g menu           # GTK Control Center (dark)
~/libyui-port/yast -r -q services-manager   # Qt
~/libyui-port/yast -r services-manager      # classic blue ncurses
~/libyui-port/yast control-center           # Qt Control Center as your user
```

### Your own programs in the Control Center

```bash
~/libyui-port/yast add-app --name "Process Monitor" --exec htop --terminal --icon utilities-system-monitor
~/libyui-port/yast add-app --name "My Script" --exec ~/bin/my-script.sh --new-section "My Tools"
~/libyui-port/yast list-apps          # remove-app NAME, list-sections, add-app --help
~/libyui-port/yast move-app "Clean pacman cache" --to Hardware     # any program, also YaST's own
~/libyui-port/yast rename-section Hardware --to "Hardware & Fans"  # any section
```

Or do it all from the Control Center: the **Add or change...** button under the search field
adds programs and sections, moves programs and renames sections. The **Section colours** box
next to it colour-codes the sections: Off, Headers, or Whole block.

No root needed; your entries and layout survive rebuilds. Details, and the manual way (a `.desktop` file
in `arch/applications/` or a section in `arch/applications/groups/`), are in
[User Guide section 5](docs/USER-GUIDE.md#5-add-your-own-app-or-section).

## Status

| layer | result |
|---|---|
| `libyui` core / Qt / GTK | builds, **zero changes** |
| `libyui-ncurses` | builds, needs the ncursesw header shim |
| `yast-core` (YCP interpreter + SCR) | builds, **zero source changes** |
| `yast-devtools` | 2 patches |
| `yast-ycp-ui-bindings` | 1 make-var override |
| `yast-ruby-bindings` | **1 patch — required for Ruby ≥ 3.4** |
| 24 YaST module repos | install clean (pure Ruby file-copy via `rake install`); for `yast-ldap` only the Ruby/Perl/SCR parts are copied, its C++ LDAP agent is not built |
| `libstorage-ng` + `yast-storage-ng` | 1 patch (honour `--prefix`) |
| `yast2-control-center` (Qt) | 3 patches |

Working modules include services-manager, bootloader, country (keyboard/timezone/language),
users, firewall, network, journal, samba client/server, nfs client/server, ntp-client,
security, sysconfig, ldap, nis-client, proxy, vpn, tftp-server, iscsi-client, alternatives,
apparmor.

**Software management is deliberately not ported.** YaST's packager is welded to libzypp/RPM;
porting it would mean writing a libalpm backend. Instead the Software group points at
[Octopi](https://github.com/aarnt/octopi), which already speaks pacman/AUR.

## The portability fixes

Nearly all of them are **path assumptions**, not architecture:

1. **ncursesw headers.** openSUSE/Debian use `/usr/include/ncursesw/`; Arch has no such
   directory and its `/usr/include/curses.h` is already wide-char. `bootstrap.sh` builds a
   symlink shim. It needs the C++ binding headers too (`etip.h`, `cursesw.h`, …), not just
   `curses.h`.
2. **docbook path** (`patches/01`) — `y2devtools.m4` searched three SUSE/Debian locations;
   Arch uses `/usr/share/xml/docbook/xsl-stylesheets`.
3. **RPM macros** (`patches/02`) — `build-tools/rpm` installs to a hardcoded
   `/usr/lib/rpm/macros.d`, ignoring `--prefix`. Meaningless on Arch; dropped.
4. **`lib64`** — `YastCommon.cmake` hardcodes `lib64` on any 64-bit host. Arch uses `lib`
   (`/usr/lib64 → lib`). Mirrored inside the prefix instead of patching.
5. **`DEVTOOLSBINDIR`** hardcoded to `/usr`; overridden at `make` time.
6. **ruby-bindings install** targets Ruby's `vendor_ruby`, ignoring `CMAKE_INSTALL_PREFIX`;
   staged via `DESTDIR`. The resulting `libpy2lang_ruby.so` must then be copied into the
   plugin dir or every `Yast.import` fails with *"component cannot import namespace"*.
7. **`fast_gettext` must be `<3.0`** — Arch ships 3.1.0. Pinned to 2.4.0 in the user gem dir.

### The one that actually mattered: Ruby 3.4 breaks YaST's embedded VM

`yast-ruby-bindings/src/binary/YRuby.cc` did this, citing a 2013 blog post and the comment
*"Copying only needed parts of `ruby_options` here"*:

```c
rb_define_module("Gem");   // pre-create an EMPTY Gem module
y2_require("rubygems");
```

On Ruby ≥ 3.4 that leaves the VM without its prelude. `rubygems/specification.rb:106`
(`Time.now.utc`) and `forwardable/impl.rb:8` (`RubyVM::InstructionSequence.compile`) then fail
with `undefined method '#<Symbol:0x...>'` — symbol names printing as raw object addresses.

`patches/03` calls the real `ruby_options(3, {"yast","-e",""})` instead: full process
initialisation including the prelude, executing nothing because the script is an empty `-e`.

This is probably the single most reusable thing here — it would affect any distro on Ruby 3.4+.

## Notes

- **SCR agents are declarative.** Retargeting a config file at Arch paths is editing a
  four-line `.scr`, not writing code (`patches/04` shows the pattern).
- **YaST needs real root.** It checks `Process.uid == 0`; being in `wheel` isn't enough. Use
  `-r`, which passes the port's `RUBYLIB`/`Y2DIR` through to root and, for GUI mode, routes via
  XWayland with `xhost +SI:localuser:root` (`xorg-xhost`). With a terminal it uses `sudo`.
  Without one (menu entries, Control Center clicks) it uses `sudo -n` if that works
  (NOPASSWD or cached credentials), otherwise `pkexec` for Qt/GTK (polkit asks for the
  password in a dialog; needs `polkit` and a running polkit agent, which every major desktop
  has), otherwise it re-opens the command in a terminal window, otherwise it shows a desktop
  notification/dialog explaining why nothing opened. `YAST_ESCALATE=sudo|pkexec|terminal`
  forces one method; `YAST_DEBUG=1` prints the chosen method and command without running it.
- **Boot loader writes are opt-in** (patch 12): `YAST_ALLOW_BOOTLOADER_WRITE=1 yast -r -q bootloader`.
  `-r` passes that variable to root only when you set it to exactly `1`; it is never set for you.
- **Upstream is pinned.** `bootstrap.sh` clones each upstream repository at the commit the
  patches were made and tested against (the `PIN` table at the top of the script). A patch
  that does not apply stops the build with a message naming it; `YAST_IGNORE_PATCH_FAILURES=1`
  continues anyway, `YAST_UPSTREAM_UNPINNED=1` clones upstream's current branches instead.
  Existing clones in `~/libyui-port` are reused as they are (with a warning if not at the pin).
- **GTK aborts if your icon theme lives in `~/.local/share/icons`.** The sandboxed glycin
  SVG loader binds only `/usr`, `/nix/store` and fonts — never `/home` — so it cannot read
  user-local themes. GTK then fails even its `image-missing` fallback and dies on
  `ensure_surface_for_gicon` with SIGABRT. Arch has no gdk-pixbuf SVG loader at all, so glycin
  cannot be bypassed. The launcher fixes this two ways, and **both are needed**: a private
  `XDG_CONFIG_HOME` (`gtkconf/`) forcing system-wide Adwaita, *and* `GTK_USE_PORTAL=0` —
  because on Wayland/KDE GTK reads its icon theme from `xdg-desktop-portal`, which **outranks
  `settings.ini`** and would otherwise drag the user-local theme straight back. Your own GTK
  settings are left untouched.
- **`/var/log/YaST2` doesn't exist on Arch** — root logging needs it created once.
- **services-manager takes 2–4 minutes to start.** It runs two `systemctl` calls per unit and a
  typical Arch box has ~1000. Not a bug.
- Harmless warnings: `Target display-manager.target / syslog.target not found` (SUSE-isms),
  Nokogiri libxml version mismatch, `already initialized constant TMP_RUBY_PREFIX`.

## Continuous integration and releases

- **CI** ([`ci.yml`](.github/workflows/ci.yml)) runs on every push and pull request to `main`. It
  runs `bootstrap.sh` from scratch in a clean `archlinux:base-devel` container, as a normal user
  with passwordless sudo, and fails if a pinned commit cannot be fetched, any patch does not
  apply, a module fails to install or anything does not build. Then it does read-only smoke
  checks (`yast --version`, `list-sections`, `add-app`/`list-apps`/`remove-app` in a throw-away
  home folder, `ag_probe --selftest`, missing libraries, `desktop-file-validate`). It never
  starts a YaST module. Logs are kept as the `ci-logs` artifact of each run.
- **Run the same check on your PC** (Docker; it builds in the container and leaves your own
  installation alone):

  ```bash
  docker run --rm -v "$PWD":/src:ro archlinux:base-devel /src/.github/ci/build-and-smoke.sh
  ```
- **Releases** ([`release.yml`](.github/workflows/release.yml)): set `VERSION`, add its section
  to `CHANGELOG.md`, then push a tag `vX.Y.Z` that equals `v` + `VERSION`. The full CI runs
  first; only if it passes is a GitHub release made with `yast-on-arch-X.Y.Z.tar.gz`, the
  patches on their own (`yast-on-arch-X.Y.Z-patches.tar.gz`), the User Guide PDF and
  `SHA256SUMS`. A release that is already published is left alone.
- **No prebuilt binaries.** The built prefix is not relocatable: about 570 of its files contain
  the absolute build path (compiled-in search paths, library RUNPATHs, SCR agent and menu
  files), and it is tied to the exact Ruby, ICU, Boost and Qt versions Arch had on the day it
  was built, so it would break after a few weeks of updates. Build it with `bootstrap.sh`.

## Licence

GPL-2.0, matching upstream YaST and libyui. The patches here are derivative of GPL-2.0 code.

## Control Center (2026-09-06)

The real `yast2-control-center` (Qt) is ported: `~/libyui-port/yast control-center`
(KDE menu: *YaST Control Center*). It runs as your user, so it follows your Qt/KDE
theme, dark mode included, and escalates each module to root through `yast -r -q`
only when you open it (`sudo -n`, else a `pkexec` password dialog; see Notes). Root modules
get a copy of your `kdeglobals`, so they match. Anything started without a terminal logs to
`$XDG_RUNTIME_DIR/yast-on-arch.log`.

Arch stand-ins live in `arch/`: `Pkg` (pacman-backed queries, no transactions),
`InstURL`/`Packages`/`SLPAPI` (installer-only, no-ops) and a small `y2storage` shim
are built into the prefix for Boot Loader, NFS and Security. Nothing needs the network at runtime.
