#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/dist/VibeCast.app"
DESTINATION="${VIBECAST_INSTALL_DIR:-/Applications}"
APP="$DESTINATION/VibeCast.app"
EXPECTED_ID="app.vibecast.mac.development"

[[ -d "$SOURCE" ]] || { echo "Build the development app first." >&2; exit 1; }
SOURCE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")"
[[ "$SOURCE_ID" == "$EXPECTED_ID" ]] || { echo "This installer is for the local development app only." >&2; exit 1; }
mkdir -p "$DESTINATION"
[[ -w "$DESTINATION" ]] || { echo "No write access to $DESTINATION. Set VIBECAST_INSTALL_DIR to ~/Applications." >&2; exit 1; }
[[ "$DESTINATION" != "$ROOT_DIR/dist" ]] || { echo "Install outside the build directory." >&2; exit 1; }
[[ ! -L "$APP" ]] || { echo "Refusing to replace a symlink at $APP." >&2; exit 1; }
if [[ -e "$APP" ]]; then
  INSTALLED_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
  [[ "$INSTALLED_ID" == "$EXPECTED_ID" ]] || { echo "A different VibeCast edition is installed at $APP; leaving it unchanged." >&2; exit 1; }
fi

STAGE="$(mktemp -d "$DESTINATION/.vibecast-install.XXXXXX")"
cleanup() {
  if [[ ! -e "$APP" && -d "$STAGE/previous.app" ]]; then
    mv "$STAGE/previous.app" "$APP"
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE" "$STAGE/VibeCast.app"
/usr/bin/codesign --verify --strict "$STAGE/VibeCast.app"

# Close only the source and destination copies, not another VibeCast edition.
while IFS= read -r PID; do
  [[ -n "$PID" ]] || continue
  COMMAND="$(ps -p "$PID" -o comm= || true)"
  if [[ "$COMMAND" == "$APP/Contents/MacOS/VibeCast" || "$COMMAND" == "$SOURCE/Contents/MacOS/VibeCast" ]]; then
    kill "$PID"
    for _ in {1..30}; do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$PID" 2>/dev/null; then
      echo "VibeCast did not exit. Quit it and retry the installation." >&2
      exit 1
    fi
  fi
done < <(pgrep -x VibeCast || true)

if [[ -d "$APP" ]]; then mv "$APP" "$STAGE/previous.app"; fi
mv "$STAGE/VibeCast.app" "$APP"
# Keep notification activation pointed at the installed copy, not the build output.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$SOURCE" >/dev/null
  "$LSREGISTER" -f "$APP" >/dev/null
fi
printf '%s\n' "$APP"
