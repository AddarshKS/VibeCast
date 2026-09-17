# VibeCast Project Status

Updated September 16, 2026.

## Accepted baseline

The owner considers UI/UX and normal player-controller functionality complete for this development milestone. After the latest dropdown layout change, the owner reported zero flutter. Preserve this baseline while working on requests; it is not a claim of public-release readiness or exhaustive device/accessibility testing.

- Shared dropdown and detachable player, fixed width, stable fullscreen anchoring, outside-click/status-icon dismissal, and an independent Settings window.
- Movable, normal-level pop-out window, menu-bar activation, immediate return to the dropdown, selective vertical resizing, and reset of custom sizes on redocking.
- Playback controls with serialized actions and confirmation guards; Spotify Connect device selection only, without changing system audio settings.
- Normal lyrics, synchronized highlighting, clickable timed lines, scrollable lyrics/queue with hidden scrollbars, and cached lyric results for the current track.
- Sparkles entry/exit button and ripple-based Lyrics Mode in both containers, with the same lyric font size. Dropdown focus retains normal lyrics height; detaching keeps focus and makes it vertically resizable.
- Quiet success feedback for player buttons; typed requests and failures remain visible. The request field, suggestions, and Adv/Player switch share the same UI in either container.
- Installed `/Applications/VibeCast.app`, monochrome branding, and packaged resources. Local development signing is not public distribution signing.

## Architecture contract

One player, two containers. Features belong to the shared player, not to a pop-out-only implementation. `MenuBarController` moves the existing hosting controller between the popover and window. `VibeCastStore` and `PlayerDetailsStore` retain playback/request/detail state; `PlayerPresentation` selects the panel and applies presentation rules.

Keep only window-specific concerns conditional: resizing, dragging, dismissal, anchoring, activation, and surface decoration. Both containers use the height AppKit has allocated, rather than displaying a larger content layout before the native surface grows. Preserve this ordering when modifying layout.

Detached standard view and Lyrics Mode can resize vertically, with a 405-point minimum subject to screen capacity. Queue and normal lyrics temporarily lock their height. Width stays at 400 points. Redocking resets only custom sizes, preserving Lyrics Mode at the normal fixed dropdown lyrics height. Panel selection, Advanced View, and drafts also survive container changes. Dropdown Lyrics Mode itself never enables resizing.

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

The latest implementation passed the full Swift test run with visual rendering (runner reported 95 tests across 12 suites; environment-gated live/native tests are not all enabled in that run), plus all 10 tests in the separately enabled native presentation suite, including repeated round trips that retain Lyrics Mode, panels, Advanced View, and draft text. The routing-only run passed four tests and the optional Node service passed nine tests at the preceding checkpoint. The installed bundle was verified running, and the owner confirmed the visual fix. Live AI playlist generation is not covered by those results.

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
- The following implementation adds dropdown Lyrics Mode, shared allocated-height layout, and preserved Lyrics Mode when popping out; it is included with this status update.
