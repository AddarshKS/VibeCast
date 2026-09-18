# Request Phase Handoff

September 18, 2026. This checkpoint closes the approved player/UI work. The next phase is request handling and the UI states caused by requests, on a new branch/PR from the latest `main`. No new request feature implementation is included in this handoff.

## Read First

- `docs/PROJECT_STATUS.md`: accepted behavior, architecture, request acceptance matrix, and explicit deferrals.
- `docs/COMPACT_DROPDOWN_EXPERIMENT.md`: player layout and presentation constraints.
- `docs/SUBSCRIPTION_BETA.md` and `RELEASE.md`: local subscription setup and release limitations.

The UI is owner-approved, not a declaration that the product is ready for public release. Preserve it unless the owner explicitly approves a change. Landing title artwork and matching its height to reading windows remain future ideas, not permission to redesign now.

## Preserve These Decisions

- One shared player in two containers. Moving between dropdown and detached window preserves the active screen, request draft, and player state. Only window-specific behavior belongs in container code.
- Dropdown opening does not activate VibeCast or require a second click. The status icon toggles it closed, including macOS 27 native menu-bar tracking. Outside clicks dismiss it. Detached activation brings the existing window forward on its own Space rather than moving it onto a fullscreen app.
- Do not reintroduce popover resize/reanchor flicker. Both containers lay out using the allocated native height. Normal lyrics/queue resize vertically only when detached; width remains 340 points.
- Immersive is the only miniplayer. The eight-dot grip belongs only to its base screen, never custom lyrics/queue. The pop-out button remains aligned across all three mini screens.
- Shared queue scrolling must preserve resisted pull/snap, initial Next Up positioning, and history-growth stability. Direct queue jumping is still deferred: do not replace Spotify's playback context or claim the sequential-skip behavior is a true direct jump.
- Player-button successes stay quiet; failures and typed-request feedback remain visible. Spotify Connect devices only, not system audio outputs.
- Inspirations retain their label-only white hover glow, three approved titles, and 22-point gap below playback. Cancel on a completed recommendation restores them immediately, preserving a new draft and diagnostic history.

## Request Work Still To Do

1. Audit existing code before replacing anything. Routing, Find confirmation, playlist planning, real-track matching, private creation, recovery, and local subscription integration already exist; passing mocked tests does not establish live acceptance.
2. Verify exact tracks, artist prompts, fuzzy moods/genres, text controls, ambiguous prompts, and chat-only requests. All Find Playlist results require confirmation before playback.
3. Verify Sure and Cast Magic via both inline and notification actions. Cast Magic must retain the original recommendation brief even if the composer draft has changed.
4. Finish live Make Playlist/Cast Magic testing: scopes, reconnects, AI allowance/errors, matching, song order/count, cancellation, interrupted writes, and duplicate prevention. Let the owner judge musical quality. There is currently no implemented Computer Use fallback.
5. Design request-specific feedback and recovery with the owner. Ordinary errors should be concise/actionable, with technical details in Adv. Successful responses currently return to inspirations after 60 seconds when safe; errors, unresolved recommendations, unfinished playlists, and fresh drafts are protected. Do not blindly clear them to satisfy a return-to-landing requirement.
6. Assess Adv against actual manual testing needs: route, stage, original prompt, resolved result, error provenance, copying/clearing logs, and secret redaction.

## Code Map

- `Sources/VibeCast/Stores/VibeCastStore.swift`: request lifetime, execution, pending recommendations, cancellation, and feedback cleanup.
- `Sources/VibeCast/Routing/RequestRouter.swift`: request routes; read related routing classifiers too.
- `Sources/VibeCast/Services/PlaylistPlanner.swift` and `MusicSearch.swift`: planning and Spotify catalog matching.
- `Sources/VibeCast/Services/Spotify/SpotifyAPIClient.swift`: playback and playlist API operations; adjacent auth/token services manage Spotify access.
- `Sources/VibeCast/Services/Subscription/ChatGPTSession.swift` and `CodexRPC.swift`: local subscription session and planner integration.
- `Sources/VibeCast/Services/Notifications/NotificationService.swift` and `Support/NotificationActionRouter.swift`: notification actions.
- `Sources/VibeCast/Views/MenuBarRootView.swift`, `RequestStatusView.swift`, `PromptComposerView.swift`, `DiagnosticsView.swift`, and `DeveloperConsole.swift`: request-facing UI and developer feedback.
- `Sources/VibeCast/App/MenuBarController.swift` and `StatusItemExpandedSession.swift`: sensitive native presentation behavior; avoid unrelated edits here.
- `Tests/VibeCastTests/`: routing, store, service, subscription, feedback, rendering, and native presentation regression coverage.

## Verification

Run Swift commands sequentially through the wrapper; this Mac's beta OS/toolchain uses the compatible SDK selected by `script/swift.sh`.

```sh
./script/run_routing_checks.sh
VIBECAST_RENDER_UI=1 ./script/swift.sh test --jobs 2
VIBECAST_TEST_PRESENTATION=1 ./script/swift.sh test --jobs 2 --filter PresentationTests
npm --prefix server test
./script/build_and_run.sh --verify
```

The presentation suite includes tests spread across `PresentationTests.swift`, `ExpandedSessionTests.swift`, `StatusItemToggleTests.swift`, and `PlayerActivationTests.swift`. Render previews are ignored under `.artifacts/previews`; native tests briefly show fixture windows. Live subscription/playlist quality testing is separate from these fixture tests. The packaged development app is installed at `/Applications/VibeCast.app`. Never expose credentials or weaken Keychain protection to avoid prompts.

For a fresh task: verify the branch and working tree, read this handoff and project status, inspect the existing request flow, then agree on the first bounded request milestone before implementing it. Earlier experimental chat instructions are historical; the accepted code and these current decisions are the baseline.
