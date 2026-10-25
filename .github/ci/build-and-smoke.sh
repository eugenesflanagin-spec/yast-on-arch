#!/bin/bash
# CI for yast-on-arch: run bootstrap.sh end-to-end in a clean Arch container,
# then do read-only smoke checks of the result.
#
# Run it as root inside a fresh archlinux:base-devel container, from a checkout
# of this repository (GitHub Actions does exactly that, see ci.yml):
#
#   docker run --rm -v "$PWD":/src:ro archlinux:base-devel /src/.github/ci/build-and-smoke.sh
#
# What it does:
#   1. pacman -Syu, creates the user "builder" with passwordless sudo
#      (bootstrap.sh runs as a normal user and calls sudo pacman itself);
#   2. runs bootstrap.sh as builder in a login shell, like a user at a terminal
#      (/etc/profile puts perl's pod2html etc. on PATH),
#      with YAST_ARCH_ROOT=/home/builder/libyui-port;
#   3. checks the log: every patch applied freshly, no module FAILed, no warnings;
#   4. smoke checks (as builder, all read-only or inside the build's own prefix):
#      yast --version, yast (client list), list-sections, add-app/list-apps/
#      remove-app with a throw-away HOME, ag_probe --selftest, missing-library
#      check, desktop-file-validate, ruby/perl/bash syntax checks.
#
# It NEVER starts a YaST module or the Control Center: modules can write system
# configuration, and with no terminal the ncurses UI walks wizards forward.
#
# Optional caches (used by ci.yml, all optional):
#   YOA_CI_CACHE=/ci-cache   gem/ = builder's user gems, src/ = upstream clones.
#                            Restored before the build; with YOA_CI_SAVE_CACHE=1
#                            written back afterwards (clones reset to their pinned,
#                            unpatched state first, so patches are always applied
#                            fresh). /var/cache/pacman/pkg is pruned to the
#                            installed versions for the caller to keep.
#   YOA_CI_OUT=/ci-out       bootstrap.log and smoke.log go here.
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$SELF")/../.." && pwd)"
CACHE="${YOA_CI_CACHE:-/ci-cache}"
OUT="${YOA_CI_OUT:-/ci-out}"
B=builder
BH=/home/$B
SRC=$BH/yast-on-arch
ROOT=$BH/libyui-port

say()  { printf '\n\033[1;36m[ci]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[ci] FAILED:\033[0m %s\n' "$*" >&2; exit 1; }

# PIN table of bootstrap.sh as "dir sha" lines
pins() { sed -n 's/^  \[\([A-Za-z0-9._-]*\)\]=\([0-9a-f]\{40\}\)$/\1 \2/p' "$1"; }

# ---------------------------------------------------------------- smoke checks
# Runs as builder (the script calls itself with --smoke).
smoke() {
  local v want n out tmp f bad=0
  cd "$ROOT"
  want="yast-on-arch $(cat "$SRC/VERSION")"

  say "yast --version"
  v="$("$ROOT/yast" --version)"; echo "$v"
  [[ "$v" == "$want" ]] || fail "yast --version printed '$v', expected '$want'"

  say "installed files"
  for f in prefix/lib/YaST2/bin/y2base prefix/destdir/usr/lib/YaST2/bin/y2controlcenter \
           prefix/lib/YaST2/servers_non_y2/ag_probe yast yast-apps yui-demo; do
    [[ -x $f ]] || fail "$ROOT/$f missing or not executable"
  done
  for f in prefix/lib/YaST2/plugin/libpy2lang_ruby.so prefix/lib/libyui.so \
           prefix/lib/libstorage-ng.so yast-env.sh VERSION \
           prefix/destdir/usr/share/YaST2/scrconf/probe.scr \
           prefix/share/augeas/lenses/login_defs.aug; do
    [[ -e $f ]] || fail "$ROOT/$f missing"
  done
  for f in qt gtk ncurses; do
    compgen -G "prefix/lib/yui/libyui-$f.so*" >/dev/null || fail "libyui-$f plugin missing in prefix/lib/yui"
  done
  ls prefix/lib/yui

  say "shared libraries resolve (ldd, same LD_LIBRARY_PATH as the launcher)"
  out="$(
    set +u
    # shellcheck disable=SC1091
    source "$ROOT/yast-env.sh" >/dev/null
    export LD_LIBRARY_PATH="$ROOT/prefix/lib:$ROOT/prefix/lib/yui:$LD_LIBRARY_PATH"
    for f in prefix/lib/YaST2/bin/y2base prefix/destdir/usr/lib/YaST2/bin/y2controlcenter \
             prefix/lib/YaST2/plugin/*.so prefix/lib/yui/*.so; do
      ldd "$f" | sed -n "s|^|$f: |; /not found/p"
    done
  )"
  [[ -z "$out" ]] || { echo "$out"; fail "unresolved shared libraries"; }
  echo "  all resolve"

  say "yast (no arguments: prints the client list)"
  out="$("$ROOT/yast" </dev/null)"
  n="$(grep -c '^  [a-z0-9_]' <<<"$out" || true)"
  echo "  $n clients listed"
  for f in menu services-manager bootloader users firewall lan journal security \
           kde_settings pacman_cache; do
    grep -qx "  $f" <<<"$out" || fail "client $f not in the yast client list"
  done
  (( n >= 80 )) || fail "only $n clients listed"

  say "yast list-sections"
  out="$("$ROOT/yast" list-sections)"; echo "$out"
  for f in System Hardware Net_advanced Security Software Misc; do
    grep -q "^$f " <<<"$out" || fail "section $f not listed"
  done

  say "yast add-app / list-apps / remove-app (throw-away HOME)"
  tmp="$(mktemp -d)"
  (
    export HOME="$tmp" XDG_DATA_HOME="$tmp/share"
    D="$ROOT/prefix/destdir/usr/share/applications/YaST2"
    "$ROOT/yast" add-app --name "CI Smoke Test" --exec true --comment "Added by the CI smoke test" \
      --keywords ci,smoke --new-section "CI Section"
    out="$("$ROOT/yast" list-apps)"; echo "$out"
    grep -q '^CISmokeTest  *CISection  *CI Smoke Test$' <<<"$out" || fail "list-apps does not show the new entry"
    "$ROOT/yast" list-sections | grep -q '^CISection .*(yours)' || fail "new section not listed"
    for f in "$D/org.archlinux.yast.User.CISmokeTest.desktop" \
             "$D/groups/org.archlinux.yast.Group.UserCISection.desktop"; do
      [[ -f $f ]] || fail "add-app did not sync $f into the prefix"
      desktop-file-validate "$f"
    done
    if "$ROOT/yast" add-app --name "Bad" --exec "definitely-not-a-program-$$" 2>/dev/null; then
      fail "add-app accepted a command that does not exist"
    fi
    if "$ROOT/yast" remove-section CISection 2>/dev/null; then
      fail "remove-section removed a section that still has entries"
    fi
    "$ROOT/yast" remove-app "CI Smoke Test"
    "$ROOT/yast" remove-section CISection
    [[ ! -e "$D/org.archlinux.yast.User.CISmokeTest.desktop" ]] || fail "remove-app left the entry in the prefix"
    [[ ! -e "$D/groups/org.archlinux.yast.Group.UserCISection.desktop" ]] || fail "remove-section left the section in the prefix"
    "$ROOT/yast" list-apps | grep -q '^(none yet' || fail "list-apps not empty after remove-app"
  )
  rm -rf "$tmp"

  say "ag_probe --selftest (read-only: prints what it reads from /sys, /proc, uname)"
  out="$(
    set +u
    # shellcheck disable=SC1091
    source "$ROOT/yast-env.sh" >/dev/null
    perl -c "$ROOT/prefix/lib/YaST2/servers_non_y2/ag_probe" 2>&1
    "$ROOT/prefix/lib/YaST2/servers_non_y2/ag_probe" --selftest
  )"
  cut -c1-200 <<<"$out"
  grep -q 'syntax OK' <<<"$out" || fail "ag_probe: perl -c failed"
  grep -q '^Read(.probe.architecture) = "x86_64"' <<<"$out" || fail "ag_probe: .probe.architecture is not x86_64"
  grep -q '^Dir(.probe) = ' <<<"$out" || fail "ag_probe: no Dir(.probe) line"

  say "desktop-file-validate"
  n=0
  for f in "$BH"/.local/share/applications/yast-*.desktop \
           "$ROOT"/prefix/destdir/usr/share/applications/YaST2/org.archlinux.yast.*.desktop \
           "$ROOT"/prefix/destdir/usr/share/applications/YaST2/groups/org.archlinux.yast.*.desktop; do
    [[ -f $f ]] || continue
    n=$((n+1))
    if grep -q '@YAST_ROOT@' "$f"; then echo "$f: @YAST_ROOT@ not substituted"; bad=1; fi
    out="$(desktop-file-validate "$f" 2>&1 || true)"
    if grep -q 'error:' <<<"$out"; then echo "$out"; bad=1; elif [[ -n $out ]]; then echo "$out"; fi
  done
  (( bad == 0 )) || fail "desktop-file-validate reported errors"
  n="$(compgen -G "$BH/.local/share/applications/yast-*.desktop" | wc -l)"
  (( n == 4 )) || fail "expected 4 menu entries in ~/.local/share/applications, found $n"
  echo "  ok"

  say "syntax checks (ruby -c, bash -n)"
  for f in "$SRC"/arch/modules/*.rb "$SRC"/arch/clients/*.rb; do
    ruby -c "$f" >/dev/null || fail "ruby -c $f"
  done
  for f in "$SRC"/bootstrap.sh "$SRC"/bin/yast "$SRC"/bin/yast-apps "$SRC"/bin/yui-demo "$SRC"/yast-env.sh; do
    bash -n "$f" || fail "bash -n $f"
  done
  echo "  ok"

  say "all smoke checks passed"
}

if [[ "${1:-}" == "--smoke" ]]; then
  smoke
  exit 0
fi

# ------------------------------------------------------------------- as root
[[ "$(id -u)" == 0 ]] || fail "run this as root inside a throw-away archlinux container (it creates a user and installs packages)"
[[ -f /etc/arch-release ]] || fail "not an Arch Linux system"
[[ -f /.dockerenv || -n "${GITHUB_ACTIONS:-}" || -n "${YOA_CI_I_AM_A_CONTAINER:-}" ]] \
  || fail "this does not look like a container; refusing to touch this system (set YOA_CI_I_AM_A_CONTAINER=1 to override)"
START=$SECONDS
mkdir -p "$OUT"

say "pacman -Syu + CI tools"
# The image is a snapshot: a full upgrade first (Arch does not support partial upgrades).
pacman -Syu --noconfirm --needed git desktop-file-utils sudo
pacman -Q | wc -l

say "user $B with passwordless sudo"
id "$B" >/dev/null 2>&1 || useradd -m -s /bin/bash "$B"
echo "$B ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-ci-builder
chmod 440 /etc/sudoers.d/90-ci-builder
visudo -cq

say "copy the repository to $SRC"
rm -rf "$SRC"; mkdir -p "$SRC"
tar -C "$REPO" --exclude=./.git -cf - . | tar -C "$SRC" -xf -
chown -R "$B:" "$SRC"

say "restore caches from $CACHE"
mkdir -p "$ROOT" "$BH/.local/share"
if [[ -d $CACHE/gem ]]; then
  rm -rf "$BH/.local/share/gem"; mv "$CACHE/gem" "$BH/.local/share/gem"; echo "  gems restored"
fi
if [[ -d $CACHE/src ]]; then
  for d in "$CACHE"/src/*/; do [[ -d $d ]] && mv "$d" "$ROOT/"; done
  rm -rf "$CACHE/src"
fi
chown -R "$B:" "$BH"
# A cached clone is only used when it is at its pinned commit; it is reset to that
# commit with no local changes, so every patch is applied fresh below.
n=0
while read -r dir sha; do
  [[ -d $ROOT/$dir ]] || continue
  head="$(sudo -u "$B" git -C "$ROOT/$dir" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$head" == "$sha" ]]; then
    sudo -u "$B" git -C "$ROOT/$dir" reset -q --hard "$sha"
    sudo -u "$B" git -C "$ROOT/$dir" clean -qfdx
    n=$((n+1))
  else
    echo "  dropping cached $dir (at ${head:-nothing}, pin is $sha)"; rm -rf "${ROOT:?}/$dir"
  fi
done < <(pins "$SRC/bootstrap.sh")
echo "  $n cached clones reused (reset to their pinned commits)"

say "bootstrap.sh as $B (log: $OUT/bootstrap.log)"
T0=$SECONDS
set +e
sudo -u "$B" -H env -u YAST_UPSTREAM_UNPINNED -u YAST_IGNORE_PATCH_FAILURES -u YAST_NO_MENU_ENTRIES \
  YAST_ARCH_ROOT="$ROOT" bash --login "$SRC/bootstrap.sh" </dev/null 2>&1 | tee "$OUT/bootstrap.log"
rc=${PIPESTATUS[0]}
set -e
echo "bootstrap.sh exit status $rc after $(( (SECONDS-T0)/60 )) min $(( (SECONDS-T0)%60 )) s"
(( rc == 0 )) || fail "bootstrap.sh exited with status $rc"

say "check the bootstrap log"
LOG="$OUT/bootstrap.log"
# bootstrap.sh prints FAIL for a failed module and goes on, so exit 0 is not enough.
if grep -n '^  FAIL ' "$LOG"; then fail "a YaST module failed to install"; fi
# (bootstrap's own warnings are coloured; config.status prints plain ones, ignored)
if grep -nF $'\033[1;33mWARNING:' "$LOG"; then fail "bootstrap printed warnings (pins / patches)"; fi
# every patch must be applied now, to a fresh clone (not "already applied")
npatch="$(find "$SRC/patches" -name '*.patch' | wc -l)"
if grep -n ': already applied$' "$LOG"; then fail "a patch was already applied (clone was not pristine)"; fi
napplied="$(grep -c '^  patch .*: applied$' "$LOG" || true)"
echo "  patches applied: $napplied of $npatch"
(( napplied == npatch )) || fail "only $napplied of $npatch patches were applied"
for f in "$SRC"/patches/*.patch; do
  grep -q "^  patch $(basename "$f"): applied$" "$LOG" || fail "$(basename "$f") was not applied"
done
# 24 Ruby module repos + yast-storage-ng
nok="$(grep -c '^  ok   ' "$LOG" || true)"
echo "  modules installed: $nok"
(( nok == 25 )) || fail "expected 25 'ok' module lines, got $nok"
grep -q 'Done\.' "$LOG" || fail "bootstrap did not reach 'Done.'"

say "smoke checks as $B (log: $OUT/smoke.log)"
set +e
sudo -u "$B" -H bash --login "$SRC/.github/ci/build-and-smoke.sh" --smoke </dev/null 2>&1 | tee "$OUT/smoke.log"
rc=${PIPESTATUS[0]}
set -e
(( rc == 0 )) || fail "smoke checks failed"

if [[ -n "${YOA_CI_SAVE_CACHE:-}" ]]; then
  say "write caches back to $CACHE"
  mkdir -p "$CACHE/src"
  while read -r dir sha; do
    [[ -d $ROOT/$dir/.git ]] || continue
    sudo -u "$B" git -C "$ROOT/$dir" reset -q --hard "$sha"
    sudo -u "$B" git -C "$ROOT/$dir" clean -qfdx
    mv "$ROOT/$dir" "$CACHE/src/"
  done < <(pins "$SRC/bootstrap.sh")
  [[ -d $BH/.local/share/gem ]] && cp -a "$BH/.local/share/gem" "$CACHE/gem"
  # keep only the package versions installed now
  pacman -Sc --noconfirm >/dev/null
  du -sh "$CACHE"/* /var/cache/pacman/pkg 2>/dev/null || true
fi

say "PASSED in $(( (SECONDS-START)/60 )) min $(( (SECONDS-START)%60 )) s"
