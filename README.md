# yast-on-arch

**openSUSE's YaST, running on Arch Linux.**

YaST was retired upstream — openSUSE Leap 16 dropped graphical YaST entirely — and no
non-SUSE port has existed since [YaST4Debian](https://en.wikipedia.org/wiki/YaST) went dormant
around 2010. This repo makes it build and run on Arch.

It ships **patches and build scripts, not vendored code**. `bootstrap.sh` clones upstream
libyui/YaST, applies the Arch fixes, and installs into a self-contained prefix
(`~/libyui-port/prefix`). Your system is untouched apart from one pacman package (`dejagnu`)
and a few user-scope gems.

```bash
git clone https://github.com/eugenesflanagin-spec/yast-on-arch
cd yast-on-arch && ./bootstrap.sh

~/libyui-port/yast -r -g menu           # GTK Control Center (dark)
~/libyui-port/yast -r -q services-manager   # Qt
~/libyui-port/yast -r services-manager      # classic blue ncurses
```

## Status

| layer | result |
|---|---|
| `libyui` core / Qt / GTK | builds, **zero changes** |
| `libyui-ncurses` | builds, needs the ncursesw header shim |
| `yast-core` (YCP interpreter + SCR) | builds, **zero source changes** |
| `yast-devtools` | 2 patches |
| `yast-ycp-ui-bindings` | 1 make-var override |
| `yast-ruby-bindings` | **1 patch — required for Ruby ≥ 3.4** |
| 23 YaST modules | install clean (pure Ruby file-copy) |

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
  `-r`, which passes the port's `RUBYLIB`/`Y2DIR` through `sudo` and, for GUI mode, routes via
  XWayland with `xhost +SI:localuser:root`.
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

## Licence

GPL-2.0, matching upstream YaST and libyui. The patches here are derivative of GPL-2.0 code.

## Control Center (2026-09-06)

The real `yast2-control-center` (Qt) is ported: `~/libyui-port/yast control-center`
(KDE menu: *YaST Control Center*). It runs as your user, so it follows your Qt/KDE
theme, dark mode included, and escalates each module to root through `yast -r -q`
only when you open it. Root modules get a copy of your `kdeglobals`, so they match.

Arch stand-ins live in `arch/`: `Pkg` (pacman-backed queries, no transactions),
`InstURL`/`Packages`/`SLPAPI` (installer-only, no-ops) and a small `y2storage` shim
are built into the prefix for Boot Loader, NFS and Security. Nothing needs the network at runtime.
