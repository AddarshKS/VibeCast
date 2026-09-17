# Architecture Review and Rebuild

Initial review: September 2026, including the then-uncommitted Milestone 4 implementation. Presentation notes updated September 16 for the compact branch's direct reading modes. See [current status](PROJECT_STATUS.md) for the accepted baseline and remaining request-flow work, and [compact experiment notes](COMPACT_DROPDOWN_EXPERIMENT.md) for branch-specific UI changes.

## Findings addressed

| Finding | Consequence | Replacement |
| --- | --- | --- |
| Retired `POST /users/{id}/playlists` and `.../tracks` routes | Playlist creation rejected despite scopes | `POST /me/playlists`, idempotent `PUT /playlists/{id}/items` |
| Local `codex exec`, filesystem searches, short process timeouts, undrained pipes | Personal login dependency and unreliable generation | Isolated per-user app-server subscription mode for the beta; optional hosted/personal Responses API providers |
| Model consumed Spotify candidate metadata | Unnecessary data transfer and conflict with Spotify AI restrictions | AI receives user brief only; candidate matching stays on Mac |
| Computer-use and chat stubs returned successful placeholder results | UI claimed functionality that wasn't implemented | Remove computer fallback; honest local conversational guidance |
| Personal Spotify app ID embedded in source | Build tied to one developer configuration | Public client ID and service origin packaged from external configuration |
| Custom prototype OAuth scheme and duplicate bundle identity | Old copies could receive callbacks/notifications | Loopback PKCE callback and new, separate development/release identities |
| One volatile pending recommendation; router registered when view appeared | Lost or misrouted actions after relaunch | Bounded persisted recommendations, account ownership, expiry, router registration at app startup |
| Recommendations marked accepted without dependable recovery | Failed actions stranded requests | Guard concurrent/repeated actions, retain retryable recommendations, inline actions |
| Notification errors ignored | Successful search with no visible action | In-app confirmation always available; delivery failure surfaced |
| Creation and population treated as one opaque operation | Empty playlists and duplicates after retries | Persist created playlist plus verified tracks before an idempotent items write |
| Multiple unowned request tasks and stale result text | Race conditions, account leakage, overlapping UI outcomes | One active operation, cancellation/generation guards, fresh result/error state |
| Refresh could overlap and error diagnostics collapsed to Forbidden | Repeated refreshes and poor recovery | Single-flight refresh, bounded 401 retry, context-sensitive errors |
| Every 404 treated as missing playback device | Incorrect playlist/search errors | Device interpretation only for player endpoints |
| Resource access depended on build-directory fallback | App could fail outside the development machine | Explicit packaged-resource lookup before SwiftPM test fallback |
| Always-visible developer diagnostics and repeated errors | Dense, confusing everyday menu | Switchable Player/Developer views with full route/action/history and bounded stage logging |
| Debug-only build script without release validation | Unsigned or unconfigured download | Configuration checks, separate identities, signing, notarization and DMG scripts |
| Script-only routing assertions, no network/store coverage | Integration failures escaped tests | Swift Testing suites, transport and store fakes, Node service tests, CI |

## Retained design

Spotify remains the playback authority; VibeCast neither streams audio nor scrapes the Spotify UI. Broad prompts use Find Playlist and always await confirmation. Cast Magic keeps the original prompt and creates private playlists without autoplay. Exact songs and direct playback controls remain available without AI.

The server handles only token exchange, session issuance, and bounded playlist planning. OAuth exchanges are bound to the configured Spotify app, so an arbitrary Spotify token from another application cannot mint a VibeCast service session. Sessions are opaque, short-lived, stored as hashes, and revocable. Usage counters survive restarts. No Spotify refresh tokens or AI prompts are persisted on the server.

The subscription beta uses the documented Codex app-server protocol, not the removed `codex exec`/computer-use fallback. It has separate Keychain sign-in, a restricted child environment, isolated home/workspace, bounded JSONL responses, request/turn deadlines, drained output pipes, cancellation, model discovery, and included-allowance checks. Authentication must be ChatGPT; failures never fall through to an API provider. See [subscription setup and limitations](SUBSCRIPTION_BETA.md).

## Shared player presentation

- `MenuBarController` retains one `NSHostingController<MenuBarRootView>`. Detaching transfers that controller to the normal-level `PlayerWindow`; redocking transfers it back to `NSPopover`. Store, request state, playback, and view implementation are shared.
- `PlayerPresentation` owns selected panel, Advanced View, miniplayer/detail state, allocated height, and remembered detached reading heights. Lyrics and queue are direct reading modes, not separate normal/focused states. Feature availability does not depend on detachment. Only container-specific behavior branches on `isDetached`.
- Both surfaces constrain the content viewport to the current native height. The dropdown previously used its desired content height before its asynchronous native resize completed, unlike the detached player. It now publishes and uses the allocated height after native resizing and anchor correction. The owner reports no remaining flutter in the updated build.
- A stable, invisible anchor panel prevents fullscreen auto-hiding menu bars from moving the popover. Local/global click monitoring handles outside clicks and right-side status icons; clicking VibeCast again closes the dropdown. These monitors do not dismiss the detached player.
- On the compact branch, width is fixed at 340 points. Detached lyrics and queue modes resize vertically to a minimum of 344 points and remember independent heights until redocking. Dropdown reading modes remain fixed at 544 points, capped to available screen space. Other screens fit content automatically but cannot be manually resized.
- The ordinary lyrics/queue controls open reading modes directly with the shared reduced-motion-aware ripple; their active buttons return to landing. The former extra sparkles toggle is removed from normal reading screens. Detaching preserves the selected mode and enables resizing. Redocking resets only custom sizes. Miniplayer reading modes remain independent, fixed-size, and retain their own header exit buttons.
- Synced lyric text uses the same 18-point font throughout the compact layout. Click-to-seek, playback controls, Spotify Connect switching, request composition, and developer diagnostics have one shared implementation. Queue selection still advances sequentially; direct jump research remains deferred by agreement.

Presentation code is concentrated in `App/MenuBarController.swift`, `Models/PlayerPresentation.swift`, and `Views/MenuBarRootView.swift`. `Views/PlayerRippleTransition.swift` owns the ripple; `Views/ReadingPlayerView.swift` owns the normal reading scaffold, while `Views/PlayerDetailsView.swift` and `Views/SyncedLyricsView.swift` own the content shared with miniplayer. Native presentation and visual tests cover both containers.

## Remaining request work

The UI/UX and normal player controls are owner-accepted, not a declaration that every request route or public-release requirement is finished. Live Cast Magic creation and musical quality remain unverified. Error presentation, terminal-request cleanup (including declined recommendations), and developer-testing usefulness need their own acceptance pass. The current idle reset deliberately preserves errors and recovery state, and declining a recommendation does not itself reset the completed request message. See the [next-phase checklist](PROJECT_STATUS.md#next-phase-request-readiness).

## Remaining external validation

Follow-up usability fixes: the menu uses a retained `NSStatusItem`/`NSPopover` presentation controller rather than an embedded `MenuBarExtra` sheet. Settings has its own retained window. Spotify's callback uses bundled, self-contained branded HTML, and the supplied monochrome icon is rendered as a trimmed alpha template. The ChatGPT `persist_failed` screenshot was reproduced by overriding `HOME`; preserving the actual macOS `HOME` restores login Keychain discovery while `CODEX_HOME` remains isolated.

- Spotify and ChatGPT sign-in and normal player behavior have been exercised by the owner. Live playlist creation/new write endpoints and independent tester accounts still need acceptance with the configured dashboard app.
- Actual AI quality has not been evaluated with a live subscription or API generation request.
- Developer ID signing, notarization, clean-install testing, and public Spotify approval require operator setup.
- Subscription mode uses the account-advertised default model unless the user selects another; personal API mode has a configurable default. Neither is a musical-quality guarantee.
- Native AppKit presentation tests and offscreen light/dark renders now cover shared-window lifetime, anchoring, sizing, and Lyrics Mode. The owner confirmed the remaining flicker is gone. These checks do not establish accessibility, every compositor/glass effect, or notification delivery on a signed distribution build; those checks remain in the release checklist.

## Sources

- [Spotify 2026 migration](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
- [Spotify redirect requirements](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)
- [Spotify quota/access rules](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)
- [Spotify policy](https://developer.spotify.com/policy)
- [OpenAI credential handling](https://developers.openai.com/api/reference/overview)
- [OpenAI structured output](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Codex app-server and ChatGPT sign-in](https://learn.chatgpt.com/docs/app-server)
