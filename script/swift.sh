#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
ACTION="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
OPTIONS=()
# The Swift 6.4 Command Line Tools ship an incomplete macOS 27 macro/build service.
# Use the installed stable SDK locally without changing xcode-select or global settings.
if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] &&
   swift --version 2>&1 | grep -q "6.4" &&
   [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  OPTIONS+=(--build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
  if [[ "$ACTION" == test ]]; then
    FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
    OPTIONS+=(--disable-xctest -Xswiftc -F -Xswiftc "$FRAMEWORKS"
      -Xlinker -F -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS")
  fi
fi
exec swift "$ACTION" "${OPTIONS[@]}" "$@"
