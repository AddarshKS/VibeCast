#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
# Stop only this checkout's bundle, never another installed VibeCast.
while IFS= read -r PID; do
  [[ -n "$PID" ]] || continue
  COMMAND="$(ps -p "$PID" -o comm=)"
  if [[ "$COMMAND" == "$ROOT_DIR/dist/VibeCast.app/Contents/MacOS/VibeCast" ]]; then
    kill "$PID"
  fi
done < <(pgrep -x VibeCast || true)
./script/package_app.sh debug
APP="$(./script/install_app.sh)"
if [[ "$MODE" == --debug ]]; then exec lldb -- "$APP/Contents/MacOS/VibeCast"; fi
/usr/bin/open "$APP"
case "$MODE" in
  --verify)
    sleep 2
    pgrep -f "$APP/Contents/MacOS/VibeCast" >/dev/null
    echo "Verified latest VibeCast bundle is running."
    ;;
  --logs|--telemetry)
    exec /usr/bin/log stream --info --style compact --predicate 'subsystem BEGINSWITH "app.vibecast.mac"'
    ;;
esac
