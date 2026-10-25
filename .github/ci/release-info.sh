#!/bin/bash
# Release helpers for the release workflow (also usable by hand).
#   release-info.sh version      -> contents of VERSION, e.g. 0.2.0
#   release-info.sh check TAG    -> fails unless TAG is exactly "v" + VERSION
#   release-info.sh notes VER    -> the CHANGELOG.md section of VER (fails if missing)
set -euo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.."

version() {
  local v
  v="$(tr -d '[:space:]' < VERSION)"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.]+)?$ ]] || { echo "VERSION '$v' is not a version number" >&2; exit 1; }
  echo "$v"
}

case "${1:-}" in
  version) version ;;
  check)
    tag="${2:?usage: release-info.sh check TAG}"
    v="$(version)"
    [[ "$tag" == "v$v" ]] || { echo "::error::tag $tag does not match VERSION $v (expected v$v)"; exit 1; }
    echo "tag $tag matches VERSION $v" ;;
  notes)
    v="${2:?usage: release-info.sh notes VERSION}"
    # from "## VER" (followed by space/end) up to the next "## " heading
    out="$(awk -v v="$v" '
      /^## / { if (on) exit; if (index($0, "## " v) == 1 && (length($0) == length("## " v) || substr($0, length("## " v) + 1, 1) == " ")) { on = 1; next } }
      on { print }' CHANGELOG.md)"
    [[ -n "${out//[[:space:]]/}" ]] || { echo "::error::CHANGELOG.md has no section '## $v'"; exit 1; }
    printf '%s\n' "$out" ;;
  *) sed -n '2,5p' "$0" >&2; exit 2 ;;
esac
