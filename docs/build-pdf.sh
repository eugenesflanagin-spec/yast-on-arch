#!/bin/bash
# Builds docs/YaST-on-Arch-User-Guide.pdf from docs/USER-GUIDE.md (needs pandoc and weasyprint).
# Run it after changing the guide; the release attaches the committed PDF.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pandoc USER-GUIDE.md -f gfm -t html5 -s --metadata pagetitle="yast-on-arch User Guide" \
  --css guide.css -o "$tmp/guide.html"
# links to files outside docs/ (../CHANGELOG.md) point at the repository on GitHub in the PDF
sed -i 's|href="\.\./|href="https://github.com/eugenesflanagin-spec/yast-on-arch/blob/main/|g' "$tmp/guide.html"
cp -r images "$tmp/" 2>/dev/null || true
cp guide.css "$tmp/"
weasyprint "$tmp/guide.html" YaST-on-Arch-User-Guide.pdf
echo "wrote docs/YaST-on-Arch-User-Guide.pdf"
