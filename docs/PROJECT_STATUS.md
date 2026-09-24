# VibeCast Project Status

UI freeze: the owner approved the compact player on `codex/compact-dropdown-experiment`, originally stacked on `codex/public-beta` (PR #1). The player-reliability integration carries that UI checkpoint forward without redesigning it. Preserve the approved UI while completing review and request readiness; further UI changes need an explicit request. See [compact player scope and verification](COMPACT_DROPDOWN_EXPERIMENT.md).

Updated September 23, 2026. The request-readiness implementation below has automated verification and is ready for owner QA; use [the owner QA checklist](REQUEST_READINESS_QA.md). Preserve [the approved baseline](REQUEST_HANDOFF.md).

## Request Readiness Implementation

The request branch now accepts polite/punctuated text controls, common command typos, consistent song/artist phrasing, and explicit artist requests. Catalog matching rejects ambiguous titles and supports conservative spelling corrections only with artist evidence. Local conversational clarification retains mood, genre, song, artist, and queue intent; it does not send ordinary conversation to an AI provider or claim to be a general chatbot. Find recommendations still require Sure.

Cast Magic retains the original recommendation when consent, scope, planning, matching, or a definite creation rejection fails. Before a create POST, an account-scoped recovery record stores the intended ordered tracks and a unique description marker. Unknown outcomes use lookup-only Check Spotify; a missing result never triggers another POST. A known draft atomically replaces the creation record. After adding songs, readback verifies private visibility, ownership, exact order/count, and an unchanged snapshot before success. Recovery survives relaunch and sign-out, remains hidden for another account, and ends only on completion, definite rejection, or explicit Stop recovery. Stop recovery leaves Spotify unchanged and validates the identity shown in its confirmation.

Existing Spotify sessions must reconnect to grant `playlist-read-private` alongside private playlist modification. The app checks this before AI generation. Cancelling prevents late responses from overwriting newer work; unknown creation and incomplete population remain recoverable. A lost queue-write response warns against blindly adding the song twice.

Normal request feedback now has Dismiss, which preserves a newer composer draft, pending decisions, recovery, and developer evidence. Cancellation returns to suggestions and records a cancelled history entry. Adv retains the original prompt, terminal outcome, and last stage after progress ends. A shared error mapper provides actionable normal feedback while diagnostics retain sanitized technical detail; credential-like values are redacted before display/copy.

The approved player layout, container behavior, controls, lyrics, immersive mode, and queue navigation are preserved. The request area gains recovery/dismiss actions and Adv gains evidence fields. Live Spotify/AI/notification acceptance and musical quality remain pending; public distribution prerequisites remain separate.

Verification: the focused routing/recovery/diagnostics run passed 54 tests across six suites. A full rendered run passed all 258 tests across 26 suites before the final notification-race regression was added. The final full run exercised 259 tests; all request and rendering checks passed, but the unchanged artwork-cache test `overlappingScreensShareOneFetchAndDecodedImage` failed three cache identity/fetch-count assertions. All four artwork tests and all 15 request-readiness tests then passed together unchanged (19 tests). No artwork implementation was changed to make that rerun pass. This intermittent result is retained rather than described as a clean full final pass. The native presentation suite passed all 26 tests on its first run. All nine optional service tests and the isolated, unauthenticated installed-Codex runtime smoke test passed. Logs and rendered QA previews are under ignored `.artifacts/request-readiness` and `.artifacts/previews`.

All four routing-script checks passed. `./script/build_and_run.sh --verify` packaged the updated development app, installed it at `/Applications/VibeCast.app`, and verified it running. This is the owner QA build, not a public distribution sign-off.

## Request Playback Milestone

September 23, 2026, on `codex/request-playback-confirmation` from `main` at `2d92c0f`: typed playback requests, resolved songs, and Sure now verify the resulting Spotify state before reporting success. Sure checks the recommended playlist context and selected device through both inline and notification actions. Confirmation reads are bounded and do not resend commands. Uncertain outcomes keep the recommendation consumed to prevent replay; definite rejections permit an explicit retry. Fresh baselines, device binding, and polling/cancellation guards preserve request ownership. Existing Adv surfaces show the execution stage and safe failure evidence.

The approved player UI, native presentation, queue navigation, quiet button feedback, and protected cleanup policy are unchanged. See [the request playback acceptance matrix](REQUEST_PLAYBACK_ACCEPTANCE.md) for scope and remaining live checks. Live owner acceptance and playlist-creation quality remain pending.

Verification: routing checks passed all four cases; focused request/service/feedback checks passed 70 tests across six suites; the full Swift run passed 201 tests across 20 suites with rendering enabled; the optional service passed all nine tests. The separate native presentation suite passed all 26 tests on its third unchanged run. Its first run had 13 visibility/toggle assertions across two tests; its second had 192 cascading visibility/anchor assertions in a different test. The three affected cases also passed on untouched `main` in a temporary checkout. These intermittent native failures are retained here rather than described as a clean first pass. No presentation implementation was modified to make the tests pass. Live Spotify playback and subscription generation were not exercised.

The development bundle was packaged, installed at `/Applications/VibeCast.app`, and verified running with `./script/build_and_run.sh --verify`. This is ready for the owner's live playback acceptance pass; it is not a public-release or live-playlist-quality sign-off.

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
- Dropdown presentation does not activate VibeCast. Its native nonactivating panel accepts mouse movement and first-click SwiftUI interactions, while the composer can receive keyboard input. Outside clicks, another app becoming active, Escape, and Space changes dismiss only the dropdown.
- On macOS 27+, status-icon interactions use AppKit's expanded-interface session so the system owns menu-bar tracking, including automatic hiding. `StatusItemExpandedSession` isolates the public Objective-C bridge needed by the local 26.5 SDK build. Closing or detaching cancels tracking; contextual clicks retain the existing menu without assigning `NSStatusItem.menu`, which would suppress the delegate. Earlier systems and programmatic redocking retain the existing presentation path. The owner accepted fullscreen auto-hide and repeated-icon dismissal on their Mac; other system versions still need release acceptance.
- The shared seek bar uses activation-style keyboard focus rather than automatic editing focus, preventing an unsolicited teal glow when a nonactivating dropdown opens. A native bitmap regression checks initial opening and reopening; deliberate keyboard navigation and accessibility adjustment remain supported.
- Runtime tracing on September 18 confirmed that repeated macOS 27 icon clicks can arrive only through the global event monitor without ending the expanded session. Native-mode local/global monitors now explicitly close on a plain left click of the open dropdown's icon; local events are consumed, and closing cancels tracking. Legacy target/action and contextual clicks remain separate. Regression coverage reproduces the missing system callback instead of supplying it artificially, and checks repeated reopening, redocking, and detached-window preservation.
- The detached player uses normal managed-window Space behavior, not `moveToActiveSpace` or `fullScreenAuxiliary`. The menu-bar icon activates the existing player without moving its frame or opting it into the current fullscreen app's Space. Cross-Space switching follows macOS window activation behavior and the user's Mission Control settings.
- Playback controls with serialized actions and confirmation guards; Spotify Connect device selection only, without changing system audio settings.
- Lyrics and queue controls open their reading modes directly, with compact song headers, playback controls below, ripple transitions, and independent remembered heights in pop-out windows. The former intermediate pages and sparkles toggle are removed.
- Synced lyric emphasis, clickable timed lines, top-to-center following, a floating sync button, hidden scrollbars, and cached lyric results for the current track. Both normal and mini lyrics share the same layout font and subtle active-line emphasis.
- Immersive is the only miniplayer: edge-to-edge artwork, a dark fade, always-visible controls, and separate fixed-size lyrics/queue screens over blurred artwork. The eight-dot drag grip is retained only in the base miniplayer window, not normal or custom reading windows. The pop-out button stays in the same position across all three mini screens. Custom reading headers retain the approved artist-to-divider spacing.
- Queue opens at Next Up, with up to five session-local history entries above it. Both normal and mini queues share the resisted pull-and-snap behavior, history-growth protections, and immediate refresh on detected track changes.
- Landing retains its title, three renamed inspirations without trailing arrows, and request field. Inspirations and playlist recommendations share a 22-point gap below playback; empty Find Playlist status views no longer introduce extra spacing. The compact ready-state fixture is 430 points tall and still grows automatically for request content. Requests remain on landing and Advanced View only. Quiet success feedback for player buttons is preserved; typed requests and failures remain visible.
- Settings, Advanced View, quit, contact, and connection status live in the menu-bar icon's right-click menu. Settings retains save-only-when-changed behavior and consistent advanced-section spacing.
- Installed `/Applications/VibeCast.app`, monochrome branding, and packaged resources. Local development signing is not public distribution signing.

## Architecture contract

One player, two containers. Features belong to the shared player, not to a pop-out-only implementation. `MenuBarController` moves the existing hosting controller between the popover and window. `VibeCastStore` and `PlayerDetailsStore` retain playback/request/detail state; `PlayerPresentation` selects the panel and applies presentation rules.

Keep only window-specific concerns conditional: resizing, dragging, dismissal, anchoring, activation, and surface decoration. Both containers use the height AppKit has allocated, rather than displaying a larger content layout before the native surface grows. Preserve this ordering when modifying layout.

Only detached normal lyrics and queue modes can resize vertically, with a 344-point minimum subject to screen capacity. Their dropdown versions use a fixed 544-point height, capped to available screen space. Width stays at 340 points. Landing, device picker, Advanced View, and miniplayer fit content automatically but cannot be manually resized. Redocking clears custom heights without clearing the selected panel, miniplayer detail, Advanced View, or draft. Artwork rendering and ripple transitions preserve view identity to avoid flashing during container or mode changes.

## Request behavior today

Request routing, recommendation confirmation, playlist planning/catalog matching, private playlist writes, and interrupted-write recovery already exist in code with mocked-service coverage. Do not mistake that for a completed live request acceptance pass.

- Find Playlist awaits Sure; Cast Magic preserves the original brief. Inline actions cover unavailable notifications.
- Cast Magic uses the selected AI provider to propose songs, matches actual Spotify tracks locally, and verifies the created playlist. Unknown creation and interrupted population have account-scoped recovery. No Computer Use fallback is currently implemented. Live creation and musical quality still require owner QA.
- `returnToSuggestionsIfIdle` currently resets completed replies after 60 seconds of inactivity when safe. It deliberately does not clear errors, notification notices, pending confirmations, unfinished playlists, or a new draft. The normal view checks this only outside reading panels and Advanced View.
- Dismissing a completed Find Playlist recommendation removes its notification and immediately restores inspirations instead of waiting for the idle timer. New draft text, developer history, newer replies, active work, and errors are preserved. Sure and Cast Magic retain their normal feedback and idle-return timing. Inspiration labels have a subtle white hover glow, not a full-width row fill; monochrome symbols and a composited label avoid layered icon flicker.
- Adv shows version, route, action, terminal outcome, last stage, original prompt, resolved item, pending search, recent success/failure/cancellation history, ChatGPT status, and copyable/clearable sanitized logs. History is bounded and in memory. Dismissing normal feedback preserves it; sign-out clears on-screen account diagnostics.

## Next phase: request readiness

1. **Cover request types end to end.** Build a repeatable matrix for exact tracks, artist requests, controls via text, broad genres/moods, Find Playlist, direct Make Playlist, notification/inline Cast Magic, ambiguous prompts, and conversational/non-music input. Check chosen route, user feedback, actual Spotify outcome, and diagnostics.
2. **Finish live playlist creation.** Test the owner's connected subscription and Spotify account first, then independent testers. Verify consent, scopes/relogin, model/allowance failures, real track matching, private visibility, usable song count, ordering, cancellation, and recovery without duplicate playlists. Listening tests decide recommendation quality.
3. **Accept error presentation.** Exercise the implemented rejection, cancellation, restrictions, authentication, rate-limit, offline, and uncertain-outcome messages against real services. Check that normal guidance is useful and Adv preserves the stage and sanitized cause.
4. **Accept terminal-request cleanup.** Verify Dismiss, cancellation, recommendation decline, idle success cleanup, Check Spotify, Finish playlist, and Stop recovery. Preserve new drafts, unresolved decisions, recovery, and diagnostic history.
5. **Accept Adv as a testing tool.** Reproduce each route and failure, compare original prompt/stage/outcome against actual behavior, and verify log copy/clear and account cleanup. Use the consolidated [owner QA matrix](REQUEST_READINESS_QA.md); record findings instead of treating fixtures as live proof.

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

September 18 pre-request checkpoint: all 183 Swift tests across 19 suites passed with rendering enabled, and all nine optional service tests passed. The separate native presentation suite passed all 26 tests on rerun. Its first run lost fixture popovers during two visibility/anchor tests (743 cascading assertions); the unchanged-code rerun passed. These desktop-interactive tests are susceptible to outside activity, so the initial failure is retained here rather than represented as a clean first pass. The owner accepted the latest player behavior and shared landing spacing. The latest app bundle was packaged and verified running after the spacing change. Live request acceptance remains the next phase; see [request handoff](REQUEST_HANDOFF.md).

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
