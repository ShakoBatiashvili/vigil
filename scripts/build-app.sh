#!/bin/bash
# Builds dist/Vigil.app from source with the Swift toolchain you already have.
# No Xcode project, no third-party dependencies, no network access needed.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.1.0"
APP="dist/Vigil.app"

echo "==> Building (release)"
swift build -c release --product VigilApp
swift build -c release --product vigil
BIN="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/VigilApp" "$APP/Contents/MacOS/Vigil"
cp "$BIN/vigil" "$APP/Contents/Helpers/vigil"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Deliberately minimal: a menu-bar agent (no Dock icon), no URL scheme, no
# privacy usage descriptions (Vigil reads no location, Bluetooth or calendar data).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Vigil</string>
	<key>CFBundleDisplayName</key><string>Vigil</string>
	<key>CFBundleIdentifier</key><string>local.vigil.app</string>
	<key>CFBundleExecutable</key><string>Vigil</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc, hardened runtime, no entitlements)"
codesign --force --options runtime --sign - "$APP/Contents/Helpers/vigil"
codesign --force --options runtime --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo
echo "Built $APP (version $VERSION)"
echo "Next: scripts/audit.sh, then scripts/install.sh"
