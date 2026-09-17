#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
: "${VIBECAST_NOTARY_PROFILE:?Set VIBECAST_NOTARY_PROFILE to your notarytool keychain profile}"
./script/swift.sh test
(cd server && npm test)
./script/package_app.sh release
APP="$ROOT_DIR/dist/VibeCast.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
SUBMISSION="$ROOT_DIR/dist/VibeCast-notary.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$VIBECAST_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/VibeCast.app"
ln -s /Applications "$STAGE/Applications"
DMG="$ROOT_DIR/dist/VibeCast-${VERSION}-${ARCH}.dmg"
hdiutil create -volname VibeCast -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$VIBECAST_CODE_SIGN_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$VIBECAST_NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
shasum -a 256 "$DMG"
echo "Ready for distribution: $DMG"
