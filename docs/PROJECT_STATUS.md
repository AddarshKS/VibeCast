# VibeCast Project Status

UI freeze: the owner approved the compact player on `codex/compact-dropdown-experiment`, originally stacked on `codex/public-beta` (PR #1). The player-reliability integration carries that UI checkpoint forward without redesigning it. Preserve the approved UI while completing review and request readiness; further UI changes need an explicit request. See [compact player scope and verification](COMPACT_DROPDOWN_EXPERIMENT.md).

Updated September 17, 2026.

## Post-Freeze Reliability Pass

The owner deferred a future landing-page title treatment and a possible height adjustment to match lyrics/queue windows. Neither is part of this pass; the accepted UI and layout remain unchanged.

Before this integration, GitHub verification found PR #1 merged to `main` before PR #2 merged to `codex/public-beta`. Both PRs were merged, but `main` at `198ca09` did not include the compact UI. The UI checkpoint `b181dcc` matches `codex/public-beta` at `0f8b468` by file tree. This integration from `codex/player-reliability` to `main` combines that complete UI checkpoint with the reliability fixes; once merged, no separate UI reconciliation PR is needed. See [reviewer setup and merge reconciliation](BOT_REVIEW_SETUP.md).

Work on `codex/player-reliability` fixes short/delayed restart confirmation, stale confirmation samples, device-bound transport commands, delayed seek confirmation, a refresh-versus-sign-in race, and recovery from transient account-restore failures. Playback 403s now distinguish known restrictions, missing scopes, and an explicit Premium requirement; unknown failures no longer assert that Premium is missing. Advanced diagnostics record the failed endpoint, safe reason classification, and observed shuffle state without raw server payloads or credentials.

Shuffle already uses Spotify's official shuffle endpoint. The reported Previous failure was a real HTTP 403, not just a confirmation timeout. On September 17, the owner retested the updated installed app and confirmed that Previous now works with Shuffle enabled. The original server refusal reason was not captured, so the successful live test should not be presented as proof of its exact cause or as a guarantee against other Spotify-side restrictions.

Direct queue/history jumping remains deferred after the owner's clarification: do not replace Spotify's playback context to simulate preserving the queue. Reading the upcoming list and starting a new list from the selection is technically different from jumping within Spotify's existing queue. Session-local Recently Played also must not be assumed to match Spotify's backward navigation stack, particularly after rewinding. The existing guarded sequential behavior remains provisional, and this audit does not declare it reliable for every history path. A future agent-based approach requires separate investigation.

Verification for this pass: 170 Swift tests across 19 suites passed with visual rendering enabled; all 17 native presentation tests passed separately; routing checks passed all four cases; the optional service passed all nine tests. New regression cases cover early/delayed restarts, slow responses that must not manufacture a restart or seek, device-bound commands, classified 403 errors without automatic retries, competing sign-in/refresh operations, and cancellation-safe account recovery. No view, presentation, or queue-navigation implementation was changed. The updated development bundle was packaged, installed at `/Applications/VibeCast.app`, and verified running.

Live verification was performed by the owner; automated inspection could read Spotify but could not open VibeCast's menu-bar-only window. If Previous is rejected again, capture the new message and the `HTTP 403 /me/player/previous; reason=...` entry in Adv, then compare the same control in Spotify. The owner approved committing, publishing, and merging this integration after the successful live test. Reviewer installation and live AI request testing remain separate work.

## Accepted baseline

The owner considers UI/UX and normal player-controller functionality complete for this development milestone. After the latest dropdown layout change, the owner reported zero flutter. Preserve this baseline while working on requests; it is not a claim of public-release readiness or exhaustive device/accessibility testing.

- Shared dropdown and detachable player at 340-point width, stable fullscreen anchoring, outside-click/status-icon dismissal, and an independent Settings window.
- Movable, normal-level pop-out window, menu-bar activation, immediate return to the dropdown, selective vertical resizing, and reset of custom sizes on redocking.
- Playback controls with serialized actions and confirmation guards; Spotify Connect device selection only, without changing system audio settings.
- Lyrics and queue controls open their reading modes directly, with compact song headers, playback controls below, ripple transitions, and independent remembered heights in pop-out windows. The former intermediate pages and sparkles toggle are removed.
- Synced lyric emphasis, clickable timed lines, top-to-center following, a floating sync button, hidden scrollbars, and cached lyric results for the current track. Both normal and mini lyrics share the same layout font and subtle active-line emphasis.
- Immersive is the only miniplayer: edge-to-edge artwork, a dark fade, always-visible controls, and separate fixed-size lyrics/queue screens over blurred artwork. The eight-dot drag grip is retained only in miniplayer windows, not normal reading windows. Custom reading headers retain the approved artist-to-divider spacing.
- Queue opens at Next Up, with up to five session-local history entries above it. Both normal and mini queues share the resisted pull-and-snap behavior, history-growth protections, and immediate refresh on detected track changes.
- Landing retains its title, spacing, three renamed inspirations without trailing arrows, and request field. Requests remain on landing and Advanced View only. Quiet success feedback for player buttons is preserved; typed requests and failures remain visible.
- Settings, Advanced View, quit, contact, and connection status live in the menu-bar icon's right-click menu. Settings retains save-only-when-changed behavior and consistent advanced-section spacing.
- Installed `/Applications/VibeCast.app`, monochrome branding, and packaged resources. Local development signing is not public distribution signing.

## Architecture contract

One player, two containers. Features belong to the shared player, not to a pop-out-only implementation. `MenuBarController` moves the existing hosting controller between the popover and window. `VibeCastStore` and `PlayerDetailsStore` retain playback/request/detail state; `PlayerPresentation` selects the panel and applies presentation rules.

Keep only window-specific concerns conditional: resizing, dragging, dismissal, anchoring, activation, and surface decoration. Both containers use the height AppKit has allocated, rather than displaying a larger content layout before the native surface grows. Preserve this ordering when modifying layout.

Only detached normal lyrics and queue modes can resize vertically, with a 344-point minimum subject to screen capacity. Their dropdown versions use a fixed 544-point height, capped to available screen space. Width stays at 340 points. Landing, device picker, Advanced View, and miniplayer fit content automatically but cannot be manually resized. Redocking clears custom heights without clearing the selected panel, miniplayer detail, Advanced View, or draft. Artwork rendering and ripple transitions preserve view identity to avoid flashing during container or mode changes.

## Request behavior today

Request routing, recommendation confirmation, playlist planning/catalog matching, private playlist writes, and interrupted-write recovery already exist in code with mocked-service coverage. Do not mistake that for a completed live request acceptance pass.

- Find Playlist awaits Sure; Cast Magic preserves the original brief. Inline actions cover unavailable notifications.
- Cast Magic uses the selected AI provider to propose songs, then matches actual Spotify tracks locally. No Computer Use fallback is currently implemented. Real creation and musical quality are still part of the next phase.
- `returnToSuggestionsIfIdle` currently resets completed replies after 60 seconds of inactivity when safe. It deliberately does not clear errors, notification notices, pending confirmations, unfinished playlists, or a new draft. The normal view checks this only outside reading panels and Advanced View.
- `dismissRecommendation` removes the pending item and notification but does not itself clear the request result/state. Immediate return to suggestions after declining is not implemented.
- Adv already shows version, route, action, execution state, resolved item, pending search/original prompt, recent requests, ChatGPT status, and copyable/clearable activity logs. History is bounded and in memory. Its adequacy for the next request-testing phase remains to be evaluated, not assumed.

## Next phase: request readiness

1. **Cover request types end to end.** Build a repeatable matrix for exact tracks, artist requests, controls via text, broad genres/moods, Find Playlist, direct Make Playlist, notification/inline Cast Magic, ambiguous prompts, and conversational/non-music input. Check chosen route, user feedback, actual Spotify outcome, and diagnostics.
2. **Finish live playlist creation.** Test the owner's connected subscription and Spotify account first, then independent testers. Verify consent, scopes/relogin, model/allowance failures, real track matching, private visibility, usable song count, ordering, cancellation, and recovery without duplicate playlists. Listening tests decide recommendation quality.
3. **Refine error presentation.** Give ordinary users concise, actionable feedback, with useful technical detail in Adv. Distinguish rejection, cancellation, Spotify restrictions/unavailability, authentication, rate limits, and uncertain playback confirmation. Never imply success before confirmation.
4. **Complete terminal-request cleanup.** Define and test return to suggestions after success, recommendation decline, cancellation, and handled failure. Preserve enough feedback to understand the outcome; do not discard a new draft, an unresolved decision, or recoverable playlist work. Keep diagnostic history after normal-view cleanup. Timing and error dismissal behavior still need implementation decisions.
5. **Validate Adv as a testing tool.** Reproduce each route and failure, check the displayed stage/original prompt/result against the actual operation, verify copying and clearing logs, and ensure secrets are not exposed. Improve missing evidence only where it materially helps testing.

### Acceptance matrix to build

| Case | Expected outcome to verify |
| --- | --- |
| `Play Peace of Blood by Citadelle` | Exact-track route and confirmed matching playback, or a useful no-match error |
| `play some EDM songs`, `late night driving` | Find recommendation; no playback until Sure |
| `play songs by Ed Sheeran` | Artist-related playlist, not a track named Songs |
| Decline a recommendation | No playback; return to suggestions with history retained |
| Cast Magic after changing the draft | Uses the recommendation's original brief, not the new draft |
| `make me a soft rock playlist` | Real, private Spotify playlist with verified tracks and useful feedback |
| `what should I play?`, `damn I'm tired` | Appropriate clarification/chat response; no unintended playback |
| Missing device, expired login, rate limit, unavailable AI allowance | Actionable error, preserved diagnostics, and a clear return path |
| Cancel or interrupt creation/population | No duplicate playlist or stale completion; recover when appropriate |

## Explicit deferrals

- Queue clicks currently advance sequentially through intervening tracks. Keep this behavior unchanged until separate direct-jump research; if no suitable mechanism exists, reconsider read-only queue behavior. Do not silently replace the Spotify context to simulate a jump.
- Public distribution still requires platform access, appropriate signing/notarization, independent-account acceptance, and release/privacy checks. No public hosted service or download release is implied by pushing the repository.

## Verification and handoff

At this UI-freeze checkpoint, the full Swift test run with visual rendering passed 154 tests across 18 suites. The separately enabled native presentation suite passed all 17 tests, including container round trips, resizing, anchoring, and retained player state. The routing-only run passed four tests, and the optional Node service passed nine tests. The owner accepted the installed UI before the freeze; no UI code was changed during the final documentation and commit pass. Environment-gated subscription smoke tests and live AI playlist generation were not enabled by these commands, and musical quality remains unvalidated.

```sh
./script/run_routing_checks.sh
VIBECAST_RENDER_UI=1 ./script/swift.sh test --jobs 2
VIBECAST_TEST_PRESENTATION=1 ./script/swift.sh test --jobs 2 --filter PresentationTests
cd server
npm test
```

Visual tests use local fixtures and write ignored previews to `.artifacts/previews`. Native tests briefly show fixture windows. Subscription smoke tests are separately opt-in and do not validate musical quality. See [release acceptance](../RELEASE.md) and [subscription setup](SUBSCRIPTION_BETA.md).

Checkpoint history before this documentation update:

- `bff9b0b`: working player, lyrics, and detachable window baseline.
- `d93e6ac`: polished Lyrics Mode, resizing, sparkles control, and menu dismissal checkpoint.
- `3832eb8`: compact player layouts, queue gestures, and hover states.
- Current UI-freeze checkpoint: immersive miniplayer and custom reading screens, direct normal reading modes, shared artwork caching, stable queue anchoring, and the owner-approved final spacing and controls.
