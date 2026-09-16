#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-debug}"
case "$MODE" in debug|release) ;; *) echo "Usage: $0 [debug|release]" >&2; exit 2 ;; esac
APP="$ROOT_DIR/dist/VibeCast.app"
CONFIG="${VIBECAST_CONFIG:-$ROOT_DIR/Config/Local.plist}"
SIGNING="${VIBECAST_CODE_SIGN_IDENTITY:-}"
if [[ "$MODE" == release && "$SIGNING" != "Developer ID Application:"* ]]; then
  echo "Release requires VIBECAST_CODE_SIGN_IDENTITY=Developer ID Application: ..." >&2
  exit 1
fi
CLIENT_ID=""
SERVICE_URL=""
AI_PROVIDER=""
if [[ -f "$CONFIG" ]]; then
  CLIENT_ID="$(/usr/libexec/PlistBuddy -c 'Print :VibeCastSpotifyClientID' "$CONFIG")"
  SERVICE_URL="$(/usr/libexec/PlistBuddy -c 'Print :VibeCastServiceURL' "$CONFIG")"
  AI_PROVIDER="$(/usr/libexec/PlistBuddy -c 'Print :VibeCastAIProvider' "$CONFIG" 2>/dev/null || true)"
fi
if [[ -z "$AI_PROVIDER" ]]; then
  if [[ -n "$SERVICE_URL" ]]; then AI_PROVIDER=hosted; else AI_PROVIDER=chatGPT; fi
fi
case "$AI_PROVIDER" in chatGPT|hosted|personalAPI) ;; *) echo "Unknown VibeCastAIProvider in configuration." >&2; exit 1 ;; esac
if [[ "$MODE" == release ]]; then
  [[ "$CLIENT_ID" =~ ^[a-fA-F0-9]{32}$ ]] || { echo "Release needs a Spotify client ID in VIBECAST_CONFIG." >&2; exit 1; }
  if [[ "$AI_PROVIDER" == hosted || -n "$SERVICE_URL" ]]; then
    [[ "$SERVICE_URL" =~ ^https://[a-zA-Z0-9.-]+(:[0-9]+)?/?$ ]] || { echo "Hosted release needs an HTTPS service origin." >&2; exit 1; }
  fi
fi
./script/swift.sh build -c "$MODE"
BIN_DIR="$(./script/swift.sh build -c "$MODE" --show-bin-path)"
STAGE="$(mktemp -d "$ROOT_DIR/dist-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/VibeCast.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/VibeCast" "$BUNDLE/Contents/MacOS/VibeCast"
cp Config/Info.plist "$BUNDLE/Contents/Info.plist"
cp -R "$BIN_DIR/VibeCast_VibeCast.bundle" "$BUNDLE/Contents/Resources/"
# SwiftPM can leave excluded artwork in an incremental resource build.
rm -f "$BUNDLE/Contents/Resources/VibeCast_VibeCast.bundle/VibeCastIcon.png" \
      "$BUNDLE/Contents/Resources/VibeCast_VibeCast.bundle/VCMenuBarIcon.png"
PLIST="$BUNDLE/Contents/Info.plist"
if [[ "$MODE" == debug ]]; then
  /usr/bin/plutil -replace CFBundleIdentifier -string app.vibecast.mac.development "$PLIST"
fi
/usr/bin/plutil -replace VibeCastSpotifyClientID -string "$CLIENT_ID" "$PLIST"
/usr/bin/plutil -replace VibeCastServiceURL -string "$SERVICE_URL" "$PLIST"
/usr/bin/plutil -replace VibeCastAIProvider -string "$AI_PROVIDER" "$PLIST"
/usr/bin/plutil -lint "$PLIST"
ICONSET="$STAGE/VibeCast.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  /usr/bin/sips -z "$SIZE" "$SIZE" Sources/VibeCast/Resources/MenuBarAppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  /usr/bin/sips -z "$DOUBLE" "$DOUBLE" Sources/VibeCast/Resources/MenuBarAppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/VibeCast.icns"
if [[ "$MODE" == release ]]; then
  /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING" "$BUNDLE"
else
  /usr/bin/codesign --force --sign "${SIGNING:--}" "$BUNDLE"
fi
/usr/bin/codesign --verify --strict --verbose=2 "$BUNDLE"
mkdir -p "$ROOT_DIR/dist"
if [[ -d "$APP" ]]; then
  rm -rf "$ROOT_DIR/dist/VibeCast.previous.app"
  mv "$APP" "$ROOT_DIR/dist/VibeCast.previous.app"
fi
mv "$BUNDLE" "$APP"
# The replaced bundle must not remain registered as a second runnable app.
if [[ -d "$ROOT_DIR/dist/VibeCast.previous.app" ]]; then
  rm -rf "$ROOT_DIR/dist/VibeCast.previous.app"
fi
echo "Packaged: $APP"
