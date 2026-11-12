#!/bin/bash
# Regenerates assets/AppIcon.icns from scripts/make-icon.swift (vector code, no third-party artwork).
# The .icns is committed, so a normal build does not need to run this.
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swift scripts/make-icon.swift "$tmp/AppIcon.iconset"
mkdir -p assets
iconutil -c icns "$tmp/AppIcon.iconset" -o assets/AppIcon.icns
echo "Wrote assets/AppIcon.icns ($(wc -c < assets/AppIcon.icns | tr -d ' ') bytes)"
