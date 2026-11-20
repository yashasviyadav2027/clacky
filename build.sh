#!/bin/bash
# Builds Clacky.app into ./build, signed with the project-local identity from
# scripts/setup-signing.sh so macOS keeps the Input Monitoring permission across rebuilds.
set -euo pipefail
cd "$(dirname "$0")"

# Universal binary: Apple Silicon + Intel.
for ARCH in arm64 x86_64; do
    swift build -c release --triple "$ARCH-apple-macosx13.0"
done
BIN=.build/Clacky-universal
lipo -create -output "$BIN" .build/arm64-apple-macosx/release/Clacky .build/x86_64-apple-macosx/release/Clacky

APP=build/Clacky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Clacky"
cp -R Resources/Packs "$APP/Contents/Resources/Packs"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.yashasviyadav.clacky</string>
    <key>CFBundleName</key><string>Clacky</string>
    <key>CFBundleExecutable</key><string>Clacky</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

KEYCHAIN="$PWD/.signing/clacky.keychain-db"
[ -f "$KEYCHAIN" ] || scripts/setup-signing.sh
security unlock-keychain -p "$(cat .signing/password)" "$KEYCHAIN"
# codesign only finds identities in the search list, so add the keychain just for this call.
ORIG_KEYCHAINS=()
while IFS= read -r kc; do ORIG_KEYCHAINS+=("$(echo "$kc" | xargs)"); done < <(security list-keychains -d user)
restore_keychains() { security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}"; }
trap restore_keychains EXIT
security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}" "$KEYCHAIN"
codesign --force --keychain "$KEYCHAIN" --sign "Clacky Local Signing" "$APP"
echo "Built $APP"
