#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp script/check_routing.swift "$TMP_DIR/main.swift"

swiftc \
  Sources/VibeCast/Models/AuthState.swift \
  Sources/VibeCast/Models/RequestRoute.swift \
  Sources/VibeCast/Models/RequestState.swift \
  Sources/VibeCast/Models/SpotifyAction.swift \
  Sources/VibeCast/Models/VibeCastRequest.swift \
  Sources/VibeCast/Models/VibeCastResult.swift \
  Sources/VibeCast/Models/RequestHistoryItem.swift \
  Sources/VibeCast/Routing/DirectCommandClassifier.swift \
  Sources/VibeCast/Routing/RequestRouter.swift \
  Sources/VibeCast/Services/Codex/CodexInterpreterClient.swift \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/routing-checks"

"$TMP_DIR/routing-checks"
