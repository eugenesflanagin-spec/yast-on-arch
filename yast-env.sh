#!/bin/bash
# Source this to get the ported YaST stack on Arch.
#   source ~/libyui-port/yast-env.sh
P="$HOME/libyui-port/prefix"
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
