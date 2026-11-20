#!/bin/bash
# Builds a universal Clacky.app and packages it for sharing:
#   dist/Clacky.dmg — drag-to-Applications disk image with install instructions
#   dist/Clacky.zip — same app, zipped
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Clacky.app/Contents/Info.plist)"
mkdir -p dist
rm -f dist/Clacky.dmg dist/Clacky.zip

STAGING="$(mktemp -d)/Clacky"
mkdir -p "$STAGING"
ditto build/Clacky.app "$STAGING/Clacky.app"
ln -s /Applications "$STAGING/Applications"
cp "packaging/How to install Clacky.txt" "$STAGING/"

hdiutil create -volname "Clacky $VERSION" -srcfolder "$STAGING" -ov -format UDZO dist/Clacky.dmg >/dev/null
# ditto (not zip) keeps the code signature intact.
ditto -c -k --sequesterRsrc --keepParent build/Clacky.app dist/Clacky.zip
rm -rf "$(dirname "$STAGING")"

echo "Packaged Clacky $VERSION:"
ls -lh dist/
