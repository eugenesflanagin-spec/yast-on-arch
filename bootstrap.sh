#!/bin/bash
# yast-on-arch -- build and run YaST on Arch Linux.
#
# Clones upstream libyui/YaST at pinned commits, applies the Arch portability
# patches in patches/, and installs everything into a self-contained prefix
# ($YAST_ARCH_ROOT, default ~/libyui-port). Outside the prefix it installs:
#   - the pacman packages in PACMAN_DEPS below (sudo pacman -S --needed)
#   - the Ruby gems in GEM_DEPS, for your user only (gem install --user-install)
#   - menu entries in ~/.local/share/applications (opt out: YAST_NO_MENU_ENTRIES=1)
#   - /etc/systemd/system/ypbind.service.d/50-yast-arch-args.conf, only if
#     ypbind-mt is installed (NIS client)
#
#   ./bootstrap.sh            # full build
#   ./bootstrap.sh --deps     # just print the dependencies and exit
#
# Environment:
#   YAST_ARCH_ROOT=<dir>            build/install location (default ~/libyui-port)
#   YAST_UPSTREAM_UNPINNED=1        clone upstream's current default branches instead of
#                                   the pinned commits below (patches may then not apply)
#   YAST_IGNORE_PATCH_FAILURES=1    warn and continue when a patch does not apply
#                                   (default: stop with an error)
#   YAST_NO_MENU_ENTRIES=1          do not install the desktop/ menu entries
set -euo pipefail

ROOT="${YAST_ARCH_ROOT:-$HOME/libyui-port}"
PREFIX="$ROOT/prefix"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACMAN_DEPS=(cmake ninja boost qt5-base gtk3 ncurses gettext libxcrypt pkgconf git
             ruby ruby-rake bison flex libtool automake autoconf dejagnu
             docbook-xsl libxslt perl-xml-writer fdupes ruby-nokogiri ruby-augeas augeas
             libxml2 json-c swig perl-crypt-smbhash xorg-xhost)
# fast_gettext MUST be <3.0; Arch ships 3.1.0, so we pin it in the user gem dir.
GEM_DEPS=("fast_gettext:<3.0" cheetah simpleidn abstract_method yast-rake prime cfa cfa_grub2 ruby-dbus)

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Upstream commits the patches in patches/ are known to apply to (and that this
# port was built and tested with). Keyed by clone directory name; libyui-qt and
# libyui-ncurses come from the libyui monorepo.
declare -A PIN=(
  [libyui]=9149299f60237acc8d360403d317854d484bcde3
  [libyui-gtk]=140d203c1a09dac97f058a5d4efb0d071d2440b8
  [yast-devtools]=9c503683e161a418492758c4483e792e996a2e49
  [yast-core]=ab3a468cee65221c2f92a29bf014352ff7652061
  [yast-ycp-ui-bindings]=a40f7591dbc6d78e726afcbf85b5e01c8d48bcc6
  [yast-ruby-bindings]=89d7cb7c10600209b404b2efb5d05b0340f5e418
  [yast-perl-bindings]=1f8c25104a79e08e24815ec7afbb6ab56bcb0b6d
  [yast-yast2]=a393fc9e01135004cd692c09b63a66c6bea282cb
  [yast-services-manager]=15debf6ab86f22a789040f41192400640b4f846d
  [yast-country]=de4395086dcda927c7b3a831cd85082956d4b0bc
  [yast-users]=093eec2173a26345b5a17fc09fa7919865006534
  [yast-firewall]=ece98713b566677c666fda514622b6a93503701d
  [yast-bootloader]=3770984fe3d9592d2d03f93579aef7aab6bdf43e
  [yast-network]=8d225599ffd14ee3c70b9af7334afa219d09bd55
  [yast-journal]=06f2bf9f27293f741ce3ac75ccd55d0690e8ede2
  [yast-samba-client]=899cb51fd8f3deb489b91a35cba9fc9bffd9004b
  [yast-samba-server]=bb4fb06520dae0c0a00afbd5f05041ef058ba12f
  [yast-nfs-client]=0d30b50f7d447ed5c7eb7c236a5cbfb78541222e
  [yast-nfs-server]=d2e8c6a44821a3e2e8fa66035f51242ef550b4ad
  [yast-ntp-client]=20ab8f4c9d69e0c192d0cea685595e5290668007
  [yast-security]=1d4fa74267b2ecd3c7d9ff0dc3f6d4d41592c50a
  [yast-sysconfig]=0e36728dc9245fc922db8023040d328d2dccf6be
  [yast-alternatives]=9a715c43aed2b432d3bbb593dc1759264a9b6ac7
  [yast-apparmor]=71c998380e6048c38b34ef8b9755c25064d04643
  [yast-iscsi-client]=c71cfe4442c6f93301ebdb5d7045c31c80b51f37
  [yast-ldap]=22e321987aa23bdf1545921e6887b2779465af0b
  [yast-nis-client]=1e40a62430fd8b36e4f8a193f9c31c8b4ac6e62b
  [yast-proxy]=a1a10f1ba8ebb99a5bc784a1ed343a7a4cb35979
  [yast-tftp-server]=b4f89756c7b4ee35aa22ed6bb53adecbae9c8942
  [yast-vpn]=11bf798bca777e8d0b35e512925911ebb022648e
  [yast-pam]=964823f65afda5e05d1b650d11e5e1c81acb27bf
  [libstorage-ng]=8b83c8cbec1ca48403f04973632d28aa2c375531
  [yast-storage-ng]=e99b22091c8a4c9b32a537d08a10f73a0beb0eec
  [yast-control-center]=c7681beece00d38b8c5fc5ac6feb1da31fdc8283
)

# clone URL DIR -- shallow clone of the pinned commit (or the default branch with
# YAST_UPSTREAM_UNPINNED=1). An existing DIR is reused as is; a warning is printed
# when it is not at the pinned commit.
clone() {
  local url="$1" dir="$2" pin="${PIN[$2]:-}" head
  [[ -n "${YAST_UPSTREAM_UNPINNED:-}" ]] && pin=""
  if [[ -d "$dir" ]]; then
    if [[ -n "$pin" ]]; then
      head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)" \
        || die "$ROOT/$dir exists but has no checked-out commit (an interrupted clone?); delete it and re-run"
      [[ "$head" == "$pin" ]] || warn "$dir: existing clone is at ${head:0:12}, pinned commit is ${pin:0:12}; leaving it as is (delete $ROOT/$dir to re-clone)"
    fi
    return 0
  fi
  if [[ -z "$pin" ]]; then
    git clone --quiet --depth=1 "$url" "$dir"
    return
  fi
  git init --quiet "$dir"
  git -C "$dir" remote add origin "$url"
  # GitHub serves any commit by full SHA; fall back to a full fetch otherwise
  git -C "$dir" fetch --quiet --depth=1 origin "$pin" 2>/dev/null \
    || git -C "$dir" fetch --quiet origin \
    || die "cannot fetch $url (delete $ROOT/$dir and retry)"
  git -C "$dir" -c advice.detachedHead=false checkout --quiet "$pin" \
    || die "$url: pinned commit $pin not found (delete $ROOT/$dir; YAST_UPSTREAM_UNPINNED=1 uses the current branch)"
}

# apply_patch DIR PATCH [STRIP] -- apply PATCH inside DIR. Already applied = skipped
# (re-runs are safe); does not apply = stop with an error, unless
# YAST_IGNORE_PATCH_FAILURES=1.
apply_patch() {
  local dir="$1" pf="$2" strip="${3:-1}" name
  name="$(basename "$pf")"
  if ( cd "$dir" && patch -s -f -R -p"$strip" --dry-run < "$pf" ) >/dev/null 2>&1; then
    echo "  patch $name: already applied"
    return 0
  fi
  if ( cd "$dir" && patch -s -f -N -p"$strip" --dry-run < "$pf" ) >/dev/null 2>&1; then
    ( cd "$dir" && patch -s -f -N -p"$strip" < "$pf" ) && echo "  patch $name: applied"
    return
  fi
  if [[ -n "${YAST_IGNORE_PATCH_FAILURES:-}" ]]; then
    warn "patch $name does NOT apply in $dir -- continuing without it (YAST_IGNORE_PATCH_FAILURES is set); that component may misbehave"
    return 0
  fi
  die "patch $name does not apply in $dir.
       Upstream probably changed the patched file (is the clone at its pinned commit?).
       See: (cd $dir && patch -p$strip --dry-run < $pf)
       To continue without this patch anyway: YAST_IGNORE_PATCH_FAILURES=1 $0"
}

if [[ "${1:-}" == "--deps" ]]; then
  echo "pacman: ${PACMAN_DEPS[*]}"; echo "gems:   ${GEM_DEPS[*]}"; exit 0
fi

[[ -f /etc/arch-release ]] || echo "warning: this targets Arch; continuing anyway"

# ---------------------------------------------------------------- dependencies
say "Installing dependencies"
# Only what is not already satisfied: pacman -T honours "provides", so a replacement
# package (autoconf-git for autoconf, ...) counts, and pacman is not asked to swap it out.
mapfile -t MISSING < <(pacman -T "${PACMAN_DEPS[@]}" || true)
if (( ${#MISSING[@]} )); then
  sudo pacman -S --needed --noconfirm "${MISSING[@]}"
else
  echo "  all pacman dependencies are already installed"
fi
for g in "${GEM_DEPS[@]}"; do
  name="${g%%:*}"; ver="${g#*:}"
  if [[ "$ver" != "$g" ]]; then gem install --user-install --no-document "$name" -v "$ver"
  else gem install --user-install --no-document "$name"; fi
done

mkdir -p "$ROOT" "$PREFIX"
cd "$ROOT"
# Arch uses lib/; YastCommon.cmake hardcodes lib64 on 64-bit. Mirror Arch's own
# /usr/lib64 -> lib symlink inside the prefix instead of patching cmake.
[[ -L "$PREFIX/lib64" ]] || { rm -rf "${PREFIX:?}/lib64"; ln -s lib "$PREFIX/lib64"; }

# FIX 1: Arch has no /usr/include/ncursesw/. Its headers live in /usr/include and
# are already wide-char. libyui-ncurses hardcodes <ncursesw/...>, so build a shim.
say "Building ncursesw compat shim"
mkdir -p "$ROOT/compat/ncursesw"
for h in curses.h ncurses.h panel.h term.h unctrl.h \
         etip.h eti.h cursesw.h cursesp.h cursesf.h cursesm.h cursesapp.h cursslk.h; do
  [[ -f /usr/include/$h ]] && ln -sf "/usr/include/$h" "$ROOT/compat/ncursesw/$h"
done

export CC=gcc CXX=g++      # many Arch setups export CC=aocc-clang; force GCC
export PKG_CONFIG_PATH="$PREFIX/share/pkgconfig:$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export PATH="$PREFIX/bin:$PREFIX/share/YaST2/data/devtools/bin:$PATH"

# ---------------------------------------------------------------------- libyui
say "Building libyui (core, ncurses, qt, gtk)"
clone https://github.com/libyui/libyui.git libyui
cmake -S libyui/libyui -B libyui/libyui/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX"
cmake --build libyui/libyui/build -j"$(nproc)" && cmake --install libyui/libyui/build

cmake -S libyui/libyui-ncurses -B libyui/libyui-ncurses/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_CXX_FLAGS="-I$ROOT/compat"
cmake --build libyui/libyui-ncurses/build -j"$(nproc)" && cmake --install libyui/libyui-ncurses/build

for f in libyui-qt libyui-gtk; do
  src="libyui/$f"; [[ -d $src ]] || { clone "https://github.com/libyui/$f.git" "$f"; src="$f"; }
  cmake -S "$src" -B "$src/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX"
  cmake --build "$src/build" -j"$(nproc)" && cmake --install "$src/build"
done

# ------------------------------------------------------------- yast-devtools
say "Building yast-devtools (patched: docbook path, drop rpm macros)"
clone https://github.com/yast/yast-devtools.git yast-devtools
apply_patch yast-devtools "$HERE/patches/01-devtools-docbook-arch-path.patch"
apply_patch yast-devtools "$HERE/patches/02-devtools-drop-rpm-macros.patch"
( cd yast-devtools
  ./build-tools/scripts/y2autoconf --bootstrap ./build-tools/
  ./build-tools/scripts/y2automake --bootstrap ./build-tools/
  rm -f acinclude.m4; cat ./build-tools/aclocal/*.m4 > acinclude.m4
  autoreconf -f -i >/dev/null
  ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" >/dev/null
  make -j"$(nproc)" >/dev/null && make install >/dev/null )

# ------------------------------------------------------------------ yast-core
say "Building yast-core (YCP interpreter + SCR) -- no source changes needed"
clone https://github.com/yast/yast-core.git yast-core
( cd yast-core
  y2tool y2autoconf >/dev/null; y2tool y2automake >/dev/null
  autoreconf --force --install >/dev/null 2>&1
  ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" >/dev/null
  make -j"$(nproc)" >/dev/null && make install >/dev/null )

# --------------------------------------------------------- ycp-ui + ruby bindings
say "Building yast-ycp-ui-bindings"
clone https://github.com/yast/yast-ycp-ui-bindings.git yast-ycp-ui-bindings
( cd yast-ycp-ui-bindings
  export CPPFLAGS="-I$PREFIX/include" CXXFLAGS="-I$PREFIX/include -O2"
  export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
  y2tool y2autoconf >/dev/null; y2tool y2automake >/dev/null
  autoreconf --force --install >/dev/null 2>&1
  ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" >/dev/null
  # DEVTOOLSBINDIR is hardcoded to /usr; override for a non-/usr prefix
  make -j"$(nproc)" DEVTOOLSBINDIR="$PREFIX/share/YaST2/data/devtools/bin" >/dev/null
  make install DEVTOOLSBINDIR="$PREFIX/share/YaST2/data/devtools/bin" >/dev/null )

say "Building yast-ruby-bindings (patched for Ruby >= 3.4)"
clone https://github.com/yast/yast-ruby-bindings.git yast-ruby-bindings
apply_patch yast-ruby-bindings "$HERE/patches/03-ruby34-full-vm-init.patch"
( cd yast-ruby-bindings
  rm -rf build
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_MODULE_PATH="$PREFIX/share/cmake/Modules" -DLIB=lib
  cmake --build build -j"$(nproc)"
  # ruby extensions install to ruby's own vendor dir, ignoring CMAKE_INSTALL_PREFIX
  make -C build install DESTDIR="$PREFIX/destdir" >/dev/null
  # the ruby language plugin must sit where the C++ component system looks
  find "$PREFIX/destdir" -name libpy2lang_ruby.so -exec cp -f {} "$PREFIX/lib/YaST2/plugin/" \; )

# ------------------------------------------------------------ yast-perl-bindings
# Users, Samba (client) and Mail are Perl modules (Users.pm, SambaAD.pm, ...).
# Builds unchanged on Perl 5.42 / GCC 16; autotools via yast-devtools, prefix-
# relative, so no DESTDIR needed. Runtime needs PERL5LIB (see yast-env.sh).
say "Building yast-perl-bindings (Perl language plugin -- Users/Samba/Mail)"
clone https://github.com/yast/yast-perl-bindings.git yast-perl-bindings
( cd yast-perl-bindings
  y2tool y2autoconf && y2tool y2automake && autoreconf --force --install >/dev/null 2>&1
  ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" >/dev/null
  make -j"$(nproc)" >/dev/null && make install >/dev/null )

# ------------------------------------------------------------- yast modules
say "Installing YaST modules (pure Ruby -- file copy, not a build)"
MODULES="yast-yast2 yast-services-manager yast-country yast-users yast-firewall
yast-bootloader yast-network yast-journal yast-samba-client yast-samba-server
yast-nfs-client yast-nfs-server yast-ntp-client yast-security yast-sysconfig
yast-alternatives yast-apparmor yast-iscsi-client yast-ldap yast-nis-client
yast-proxy yast-tftp-server yast-vpn yast-pam"
# Arch adaptations of upstream Ruby, applied in the clone before rake install:
#   09 yast-bootloader: grub-* binaries and /boot/grub instead of grub2-* and /boot/grub2
#   10 yast-yast2 Arch.rb: uname -m fallback (no libhd .probe agent here)
#   11 yast-yast2 PackageSystem.rb: ask the pacman-backed Pkg instead of rpm
#   14 yast-security: show live /proc/sys values when no sysctl file sets a key
#   15 yast-yast2 ShadowConfig: edit /etc/login.defs itself (no login.defs.d on Arch)
#   16 yast-country Language: LANG=C.UTF-8 (stock Arch) is "not localized", not an error
declare -A REPO_PATCHES=(
  [yast-bootloader]="09-bootloader-arch-grub-paths 12-bootloader-write-guard"
  [yast-yast2]="10-yast2-arch-uname-fallback 11-packagesystem-no-rpm 15-yast2-shadow-config-no-login-defs-d"
  [yast-users]="13-users-x500dn-lazy-require"
  [yast-security]="14-security-live-sysctl-values"
  [yast-country]="16-country-language-posix-locale 17-country-console-magic-no-sysconfig"
  [yast-tftp-server]="18-tftp-arch-confd-and-units"
  [yast-nis-client]="19-nis-ypbind-arch-confd"
)
for m in $MODULES; do
  clone "https://github.com/yast/$m.git" "$m"
  for pf in ${REPO_PATCHES[$m]:-}; do
    apply_patch "$m" "$HERE/patches/$pf.patch"
  done
  ( cd "$m" && rake install DESTDIR="$PREFIX/destdir" >/dev/null 2>&1 ) \
    && echo "  ok   $m" || echo "  FAIL $m"
done

# FIX: menu.rb shells out to /sbin/yast2, which does not exist on Arch. Point it
# at our y2base instead, reusing whichever UI the Control Center was started with.
# (Patch paths are relative to destdir: usr/share/YaST2/clients/menu.rb.)
[[ -f "$PREFIX/destdir/usr/share/YaST2/clients/menu.rb" ]] \
  && apply_patch "$PREFIX/destdir" "$HERE/patches/05-menu-launch-via-y2base.patch"

# ------------------------------------------------------------- libstorage-ng
# Storage layer for Bootloader, NFS, Security. Patch 08: honour --prefix in the
# three Makefile.am places that hardcode /usr. ⛔ No blanket DESTDIR here: only
# the Ruby extension dir is a system path, everything else is prefix-rooted,
# so DESTDIR would double-prefix the C++ library. Override that one dir instead.
say "Building libstorage-ng (+ Ruby bindings) and installing yast-storage-ng"
RB="$PREFIX/destdir/usr/lib/ruby/vendor_ruby/$(ruby -e 'puts RbConfig::CONFIG["ruby_version"]')/$(ruby -e 'puts RbConfig::CONFIG["arch"]')"
clone https://github.com/openSUSE/libstorage-ng.git libstorage-ng
( cd libstorage-ng
  apply_patch . "$HERE/patches/08-libstorage-ng-honour-prefix.patch"
  libtoolize -q && aclocal && autoconf && autoheader && automake --add-missing --foreign >/dev/null 2>&1
  utils/git2log --version VERSION
  ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib" >/dev/null
  make -j"$(nproc)" >/dev/null && make install rubyextensiondirdir="$RB" >/dev/null )
clone https://github.com/yast/yast-storage-ng.git yast-storage-ng
( cd yast-storage-ng && rake install DESTDIR="$PREFIX/destdir" >/dev/null 2>&1 ) && echo "  ok   yast-storage-ng"

Y2="$PREFIX/destdir/usr/share/YaST2"
# yast-ldap is autotools (C++ LDAP agent + Ruby/Perl modules); rake install does
# nothing for it. Copy the Ruby/Perl/SCR parts -- Samba Server imports Ldap.
# (The C++ .ldap agent is not built; LDAP-backed features stay unavailable.)
if [[ -d yast-ldap/src ]]; then
  ( cd yast-ldap
    install -Dm644 src/Ldap.rb "$Y2/modules/Ldap.rb"
    install -Dm644 src/LdapPopup.rb "$Y2/modules/LdapPopup.rb"
    install -Dm644 src/LdapServerAccess.pm "$Y2/modules/LdapServerAccess.pm"
    install -Dm644 src/ldap_browser.rb "$Y2/clients/ldap_browser.rb"
    install -Dm644 src/ldap_config.rb "$Y2/clients/ldap_config.rb"
    install -Dm644 src/routines.rb "$Y2/include/ldap/routines.rb"
    install -Dm644 src/ui.rb "$Y2/include/ldap/ui.rb"
    install -Dm644 conf/ldap.scr "$Y2/scrconf/ldap.scr"
    install -Dm644 conf/ldap_conf.scr "$Y2/scrconf/ldap_conf.scr" )
fi

# Arch stand-ins for namespaces that cannot exist here (see arch/modules/*.rb):
#   Pkg      -- libzypp bindings; pacman-backed queries, transactions refused
#   InstURL, Packages, SLPAPI -- installer/SLP-only, no-ops
say "Installing Arch stand-in modules and vendored libs"
for f in "$HERE"/arch/modules/*.rb; do install -Dm644 "$f" "$Y2/modules/$(basename "$f")"; done
# arch/lib: cfa/grub2 copies that shadow the cfa_grub2 gem (/boot/grub, not /boot/grub2)
( cd "$HERE/arch/lib" && find . -type f -name '*.rb' -exec install -Dm644 {} "$Y2/lib/{}" \; )
# arch/clients + arch/applications: Arch-only panels (KDE System Settings browser --
# deliberately RootOnly=false, KCMs write per-user config)
for f in "$HERE"/arch/clients/*.rb; do install -Dm644 "$f" "$Y2/clients/$(basename "$f")"; done
for f in "$HERE"/arch/applications/*.desktop; do install -Dm644 "$f" "$PREFIX/destdir/usr/share/applications/YaST2/$(basename "$f")"; done
# arch/applications/groups: extra Control Center sections (group .desktop files)
for f in "$HERE"/arch/applications/groups/*.desktop; do
  [[ -f "$f" ]] || continue
  install -Dm644 "$f" "$PREFIX/destdir/usr/share/applications/YaST2/groups/$(basename "$f")"
done


# FIX: the Ruby layer hardcodes /usr for desktop files/data; follow Y2DIR instead.
apply_patch "$PREFIX/destdir" "$HERE/patches/06-directory-prefix-paths.patch"

# SCR agents are declarative: retarget the desktop-file paths at our prefix.
D="$PREFIX/destdir/usr/share/applications/YaST2"
for f in yast2_desktop yast2_groups; do
  s="$PREFIX/destdir/usr/share/YaST2/scrconf/$f.scr"
  [[ -f $s ]] && sed -i "s|/usr/share/applications/YaST2|$D|g" "$s"
done

# arch/applications entries name the launcher as @YAST_ROOT@/yast; fill in the real path.
sed -i "s|@YAST_ROOT@|$ROOT|g" "$D"/org.archlinux.yast.*.desktop

# Software management: YaST's packager is welded to libzypp/RPM, so we point the
# Software group at Octopi (pacman/AUR) instead.
if command -v octopi >/dev/null; then
  mkdir -p "$D"
  rm -f "$D/org.archlinux.yast.OctopiCache.desktop"   # replaced by arch/clients/pacman_cache.rb
  cat > "$D/org.archlinux.yast.Octopi.desktop" <<'EOD'
[Desktop Entry]
Type=Application
Categories=Settings;System;Qt;X-SuSE-YaST;X-SuSE-YaST-Software;
X-SuSE-YaST-Group=Software
X-SuSE-YaST-SortKey=05
X-SuSE-YaST-RootOnly=false
Icon=octopi
Exec=octopi
Name=Software Management (Octopi)
GenericName=Package Manager
Comment=Install, remove and update packages with pacman/AUR via Octopi
StartupNotify=true
EOD
fi

# GTK front-end needs a system-wide icon theme: the sandboxed glycin SVG loader
# binds only /usr, so themes under ~/.local/share/icons abort GTK on startup.
mkdir -p "$PREFIX/gtkconf/gtk-3.0" "$PREFIX/gtkconf/gtk-4.0"
install -Dm644 "$HERE/gtkconf/gtk-3.0/settings.ini" "$PREFIX/gtkconf/gtk-3.0/settings.ini"
install -Dm644 "$HERE/gtkconf/gtk-3.0/settings.ini" "$PREFIX/gtkconf/gtk-4.0/settings.ini"

# ------------------------------------------------------- yast-control-center
# The classic Qt Control Center (search bar, group sidebar, icon grid). Runs as
# the plain user (follows the desktop's Qt/KDE theme, dark mode included) and
# escalates each module through bin/yast -r -q on click. Patch 07: launch via
# $YAST_LAUNCHER instead of /sbin/yast2, theme dir follows the prefix, RootOnly
# modules stay visible, never launch an empty client.
say "Building yast-control-center (Qt)"
clone https://github.com/yast/yast-control-center.git yast-control-center
( cd yast-control-center
  apply_patch . "$HERE/patches/07-control-center-launcher-and-prefix.patch"
  apply_patch . "$HERE/patches/20-control-center-search-perf.patch"
  apply_patch . "$HERE/patches/21-control-center-search-group-sidebar.patch"
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX/destdir/usr" \
    -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_MODULE_PATH="$PREFIX/share/cmake/Modules" -DVERSION=4.7.0 >/dev/null
  cmake --build build -j"$(nproc)" >/dev/null && cmake --install build >/dev/null )
mkdir -p "$PREFIX/qtconf"   # root Qt modules get a copy of the user's kdeglobals here

# NIS client writes /etc/conf.d/ypbind (patch 19); ypbind-mt's unit takes flags on the command
# line, so this drop-in turns that file into flags. The ONE thing bootstrap puts outside the
# prefix, and only when ypbind-mt is installed (it is inert otherwise, so skip it).
if pacman -Q ypbind-mt >/dev/null 2>&1; then
  sudo install -Dm644 "$HERE/arch/systemd/ypbind.service.d/50-yast-arch-args.conf" \
    /etc/systemd/system/ypbind.service.d/50-yast-arch-args.conf && sudo systemctl daemon-reload
fi

# Arch-adapted augeas lenses (Security module: Arch's login.defs has a bare MOTD_FILE)
install -Dm644 "$HERE/arch/augeas/login_defs.aug" "$PREFIX/share/augeas/lenses/login_defs.aug"
# yast2's helper scripts and the modules' SCR script agents (ag_exports, ag_passwd,
# ...) land under destdir; y2base looks in the prefix's lib/YaST2/{bin,servers_non_y2}
for f in "$PREFIX"/destdir/usr/lib/YaST2/bin/*; do
  [[ $(basename "$f") == y2controlcenter ]] || ln -sf "$f" "$PREFIX/lib/YaST2/bin/$(basename "$f")"
done
mkdir -p "$PREFIX/lib/YaST2/servers_non_y2"
for f in "$PREFIX"/destdir/usr/lib/YaST2/servers_non_y2/*; do
  ln -sf "$f" "$PREFIX/lib/YaST2/servers_non_y2/$(basename "$f")"
done
# Arch .probe SCR agent (hwinfo replacement, Perl): .architecture .netcard .disk
# .system .is_xen .is_vmware from /sys, /proc and uname. See docs/probe-agent.md.
install -Dm755 "$HERE/arch/agents/ag_probe" "$PREFIX/lib/YaST2/servers_non_y2/ag_probe"
install -Dm644 "$HERE/arch/scrconf/probe.scr" "$Y2/scrconf/probe.scr"

install -Dm755 "$HERE/bin/yast"     "$ROOT/yast"
install -Dm755 "$HERE/bin/yast-apps" "$ROOT/yast-apps"   # yast add-app / remove-app / list-apps
install -Dm644 "$HERE/VERSION"       "$ROOT/VERSION"
install -Dm755 "$HERE/bin/yui-demo" "$ROOT/yui-demo"
install -Dm644 "$HERE/yast-env.sh"  "$ROOT/yast-env.sh"

# Menu entries (desktop/*.desktop) with the real launcher path. A same-named file
# that bootstrap did not write (no X-YaST-On-Arch-Generated key) is left alone.
if [[ -z "${YAST_NO_MENU_ENTRIES:-}" ]]; then
  say "Installing menu entries"
  APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
  mkdir -p "$APPS"
  for f in "$HERE"/desktop/*.desktop; do
    dst="$APPS/$(basename "$f")"
    if [[ -e "$dst" ]] && ! grep -q '^X-YaST-On-Arch-Generated=true' "$dst"; then
      echo "  kept $dst (not written by bootstrap; delete it to get the generated one)"
      continue
    fi
    sed -e "s|@YAST_ROOT@|$ROOT|g" -e '/^\[Desktop Entry\]/a X-YaST-On-Arch-Generated=true' "$f" > "$dst.tmp"
    mv -f "$dst.tmp" "$dst"
    echo "  $dst"
  done
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$APPS" 2>/dev/null || true
fi

# Entries added with "yast add-app" live in ~/.local/share/yast-on-arch/applications;
# copy them into the (possibly rebuilt) prefix again.
if [[ -d "${XDG_DATA_HOME:-$HOME/.local/share}/yast-on-arch/applications" ]]; then
  say "Restoring your own Control Center entries (yast add-app)"
  "$ROOT/yast-apps" sync-apps || warn "could not restore your own entries; run: $ROOT/yast sync-apps"
fi

say "Done."
cat <<EOM

  source $ROOT/yast-env.sh

  $ROOT/yast                      # list modules
  $ROOT/yast services-manager     # ncurses (classic blue)
  $ROOT/yast -q services-manager  # Qt
  $ROOT/yast control-center       # classic Qt Control Center (as user; modules escalate on click)
  $ROOT/yast -r -g menu           # GTK Control Center, dark mode, as root
  $ROOT/yast add-app --help       # add your own programs to the Control Center

  Note: services-manager takes 2-4 min to start -- it runs two systemctl
  calls per unit and a typical Arch box has ~1000 of them.
EOM
