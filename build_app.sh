#!/bin/zsh
# Builds TidyMac as a universal (Apple Silicon + Intel) binary and wraps it in a signed .app.
#   ./build_app.sh                         ad-hoc signed (macOS forgets Full Disk Access on every rebuild)
#   TIDYMAC_SIGN_ID="My Cert" ./build_app.sh   signed with a certificate from your keychain, so the grant sticks
#   ./build_app.sh --zip                   also writes build/TidyMac-<version>.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.0.0                                  # keep in step with CHANGELOG.md
ARCHS=(--arch arm64 --arch x86_64)
BUILD=$(date +%Y%m%d%H%M)
SIGN_ID=${TIDYMAC_SIGN_ID:--}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
if [ ! -d "$DEVELOPER_DIR" ]; then
  echo "Xcode not found at $DEVELOPER_DIR. Install Xcode or set DEVELOPER_DIR." >&2; exit 1
fi

swift build -c release "${ARCHS[@]}"
BIN=$(swift build -c release "${ARCHS[@]}" --show-bin-path)/TidyMac
APP=build/TidyMac.app

pkill -x TidyMac 2>/dev/null && sleep 1 || true   # a running copy would keep the old binary open
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TidyMac"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Translations: the string catalog becomes one <language>.lproj per translation. English is the text in the
# source code, so its folder only has to exist for macOS to offer English.
xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/en.lproj"
[ -f "$APP/Contents/Resources/en.lproj/Localizable.strings" ] || echo '/* English is the source language. */' > "$APP/Contents/Resources/en.lproj/Localizable.strings"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
<key>CFBundleName</key><string>TidyMac</string>
<key>CFBundleDisplayName</key><string>TidyMac</string>
<key>CFBundleIdentifier</key><string>local.tidymac</string>
<key>CFBundleExecutable</key><string>TidyMac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 mericlomlu. All rights reserved.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --sign "$SIGN_ID" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD, $(lipo -archs "$APP/Contents/MacOS/TidyMac"), signed with ${SIGN_ID/#-/ad-hoc identity})"
if [ "${1:-}" = "--zip" ]; then
  ZIP=build/TidyMac-$VERSION.zip
  rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"   # ditto keeps the signature intact
  echo "Zipped $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
fi
