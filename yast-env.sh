#!/bin/bash
# Source this to get the ported YaST stack on Arch.
#   source ~/libyui-port/yast-env.sh
# BASH_SOURCE is bash-only; when sourced from zsh/fish it is empty and the path
# silently resolves to $PWD. Fall back to a known location.
_src="${BASH_SOURCE[0]:-${(%):-%x}}"
if [ -n "$_src" ] && [ -f "$_src" ]; then
  P="$(cd "$(dirname "$(readlink -f "$_src")")" && pwd)/prefix"
else
  P="${YAST_ARCH_ROOT:-$HOME/libyui-port}/prefix"
fi
unset _src
[ -d "$P" ] || { echo "yast-env.sh: prefix not found at $P" >&2; }
RBV="$(ruby -e 'puts RUBY_VERSION.split(".")[0,2].join(".") + ".0"')"
ARCH="$(ruby -e 'puts RbConfig::CONFIG["arch"]')"
D="$P/destdir/usr/lib/ruby/vendor_ruby/$RBV"
export PATH="$P/bin:$P/share/YaST2/data/devtools/bin:$PATH"
export LD_LIBRARY_PATH="$P/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$P/share/pkgconfig:$P/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export RUBYLIB="$D:$D/$ARCH${RUBYLIB:+:$RUBYLIB}"
# fast_gettext (<3.0 required; Arch ships 3.1.0) is in the per-user gem dir.
# Do NOT override GEM_HOME -- that hides it. Just make sure the user dir is on the path.
# y2base embeds its own Ruby and does NOT activate rubygems, so gem lib dirs must be on
# RUBYLIB directly or `require "fast_gettext"` fails inside y2base.
export GEM_PATH="$(ruby -e 'puts Gem.user_dir')${GEM_PATH:+:$GEM_PATH}"
GEMLIBS="$(ruby -e 'require "rubygems"; puts Gem::Specification.group_by(&:name).map { |_,v| v.max_by(&:version) }.flat_map(&:full_require_paths).uniq.join(":")' 2>/dev/null)"
export RUBYLIB="$RUBYLIB:$GEMLIBS"
export Y2DIR="$P/share/YaST2"
export Y2BASE_PLUGINDIR="$P/lib/YaST2/plugin"
export CC=gcc CXX=g++          # avoid the AOCC leak (CC=aocc-clang is exported system-wide)
echo "YaST-on-Arch env active (prefix: $P)"

# Perl language plugin (yast-perl-bindings): YaST::YCP lives under the prefix's
# perl vendor dir, and ycp.pm (used by YaPI.pm) comes from yast-core's agents-perl
# in share/perl5 -- without BOTH, `import "Users"` dies with "Can't locate ycp.pm",
# which looks like a build failure but is only @INC.
PERLVER="$(perl -V:version 2>/dev/null | sed "s/.*='//;s/'.*//" | cut -d. -f1,2)"
export PERL5LIB="$P/lib/perl5/${PERLVER:-5.42}/vendor_perl:$P/share/perl5/vendor_perl${PERL5LIB:+:$PERL5LIB}"

# libstorage-ng hardcodes /usr/share/libstorage for its udev filters; upstream's
# own escape hatch is LIBSTORAGE_CONFDIR (checked first in UdevFilters.cc).
export LIBSTORAGE_CONFDIR="$P/share/libstorage"
