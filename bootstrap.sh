#!/bin/bash
# yast-on-arch -- build and run YaST on Arch Linux.
#
# Clones upstream libyui/YaST, applies the Arch portability patches in patches/,
# and installs everything into a self-contained prefix. Nothing outside the
# prefix is touched except one pacman package (dejagnu) and some user-scope gems.
#
#   ./bootstrap.sh            # full build
#   ./bootstrap.sh --deps     # just print the dependencies and exit
set -euo pipefail

ROOT="${YAST_ARCH_ROOT:-$HOME/libyui-port}"
PREFIX="$ROOT/prefix"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACMAN_DEPS=(cmake ninja boost qt5-base gtk3 ncurses gettext libxcrypt pkgconf git
             ruby ruby-rake bison flex libtool automake autoconf dejagnu
             docbook-xsl libxslt perl-xml-writer fdupes ruby-nokogiri)
# fast_gettext MUST be <3.0; Arch ships 3.1.0, so we pin it in the user gem dir.
GEM_DEPS=("fast_gettext:<3.0" cheetah simpleidn abstract_method yast-rake prime)

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "--deps" ]]; then
  echo "pacman: ${PACMAN_DEPS[*]}"; echo "gems:   ${GEM_DEPS[*]}"; exit 0
fi

[[ -f /etc/arch-release ]] || echo "warning: this targets Arch; continuing anyway"

# ---------------------------------------------------------------- dependencies
say "Installing dependencies"
sudo pacman -S --needed --noconfirm "${PACMAN_DEPS[@]}"
for g in "${GEM_DEPS[@]}"; do
  name="${g%%:*}"; ver="${g#*:}"
  if [[ "$ver" != "$g" ]]; then gem install --user-install --no-document "$name" -v "$ver"
  else gem install --user-install --no-document "$name"; fi
done

mkdir -p "$ROOT" "$PREFIX"
cd "$ROOT"
# Arch uses lib/; YastCommon.cmake hardcodes lib64 on 64-bit. Mirror Arch's own
# /usr/lib64 -> lib symlink inside the prefix instead of patching cmake.
[[ -L "$PREFIX/lib64" ]] || { rm -rf "$PREFIX/lib64"; ln -s lib "$PREFIX/lib64"; }

# FIX 1: Arch has no /usr/include/ncursesw/. Its headers live in /usr/include and
# are already wide-char. libyui-ncurses hardcodes <ncursesw/...>, so build a shim.
say "Building ncursesw compat shim"
mkdir -p "$ROOT/compat/ncursesw"
for h in curses.h ncurses.h panel.h term.h unctrl.h \
         etip.h eti.h cursesw.h cursesp.h cursesf.h cursesm.h cursesapp.h cursslk.h; do
  [[ -f /usr/include/$h ]] && ln -sf "/usr/include/$h" "$ROOT/compat/ncursesw/$h"
done

clone() { [[ -d "$2" ]] || git clone --quiet --depth=1 "$1" "$2"; }

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
( cd yast-devtools
  git apply --check "$HERE/patches/01-devtools-docbook-arch-path.patch" 2>/dev/null \
    && git apply "$HERE/patches/01-devtools-docbook-arch-path.patch" || true
  git apply --check "$HERE/patches/02-devtools-drop-rpm-macros.patch" 2>/dev/null \
    && git apply "$HERE/patches/02-devtools-drop-rpm-macros.patch" || true
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
( cd yast-ruby-bindings
  git apply --check "$HERE/patches/03-ruby34-full-vm-init.patch" 2>/dev/null \
    && git apply "$HERE/patches/03-ruby34-full-vm-init.patch" || true
  rm -rf build
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_MODULE_PATH="$PREFIX/share/cmake/Modules" -DLIB=lib
  cmake --build build -j"$(nproc)"
  # ruby extensions install to ruby's own vendor dir, ignoring CMAKE_INSTALL_PREFIX
  make -C build install DESTDIR="$PREFIX/destdir" >/dev/null
  # the ruby language plugin must sit where the C++ component system looks
  find "$PREFIX/destdir" -name libpy2lang_ruby.so -exec cp -f {} "$PREFIX/lib/YaST2/plugin/" \; )

# ------------------------------------------------------------- yast modules
say "Installing YaST modules (pure Ruby -- file copy, not a build)"
MODULES="yast-yast2 yast-services-manager yast-country yast-users yast-firewall
yast-bootloader yast-network yast-journal yast-samba-client yast-samba-server
yast-nfs-client yast-nfs-server yast-ntp-client yast-security yast-sysconfig
yast-alternatives yast-apparmor yast-iscsi-client yast-ldap yast-nis-client
yast-proxy yast-tftp-server yast-vpn"
for m in $MODULES; do
  clone "https://github.com/yast/$m.git" "$m" || continue
  ( cd "$m" && rake install DESTDIR="$PREFIX/destdir" >/dev/null 2>&1 ) \
    && echo "  ok   $m" || echo "  FAIL $m"
done

# SCR agents are declarative: retarget the desktop-file paths at our prefix.
D="$PREFIX/destdir/usr/share/applications/YaST2"
for f in yast2_desktop yast2_groups; do
  s="$PREFIX/destdir/usr/share/YaST2/scrconf/$f.scr"
  [[ -f $s ]] && sed -i "s|/usr/share/applications/YaST2|$D|g" "$s"
done

# Software management: YaST's packager is welded to libzypp/RPM, so we point the
# Software group at Octopi (pacman/AUR) instead.
if command -v octopi >/dev/null; then
  mkdir -p "$D"
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

install -Dm755 "$HERE/bin/yast"     "$ROOT/yast"
install -Dm755 "$HERE/bin/yui-demo" "$ROOT/yui-demo"
install -Dm644 "$HERE/yast-env.sh"  "$ROOT/yast-env.sh"

say "Done."
cat <<EOM

  source $ROOT/yast-env.sh

  $ROOT/yast                      # list modules
  $ROOT/yast services-manager     # ncurses (classic blue)
  $ROOT/yast -q services-manager  # Qt
  $ROOT/yast -g menu              # GTK Control Center, dark mode

  Note: services-manager takes 2-4 min to start -- it runs two systemctl
  calls per unit and a typical Arch box has ~1000 of them.
EOM
