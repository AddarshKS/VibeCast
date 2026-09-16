# Architecture Review and Rebuild

Reviewed September 2026. This review included the existing, uncommitted Milestone 4 implementation.

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

## Remaining external validation

Follow-up usability fixes: the menu uses a retained `NSStatusItem`/`NSPopover` presentation controller rather than an embedded `MenuBarExtra` sheet. Settings has its own retained window. Spotify's callback uses bundled, self-contained branded HTML, and the supplied monochrome icon is rendered as a trimmed alpha template. The ChatGPT `persist_failed` screenshot was reproduced by overriding `HOME`; preserving the actual macOS `HOME` restores login Keychain discovery while `CODEX_HOME` remains isolated.

- Live Spotify OAuth and new endpoint behavior must be tested with the configured dashboard app.
- Actual AI quality has not been evaluated with a live subscription or API generation request.
- Developer ID signing, notarization, clean-install testing, and public Spotify approval require operator setup.
- Subscription mode uses the account-advertised default model unless the user selects another; personal API mode has a configurable default. Neither is a musical-quality guarantee.
- Native screen automation was unavailable in this environment. Offscreen AppKit renders validate content layout, but they do not capture all compositor-backed glass effects. Live light/dark-mode, accessibility, and notification testing remains required.

## Sources

- [Spotify 2026 migration](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)
- [Spotify redirect requirements](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)
- [Spotify quota/access rules](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)
- [Spotify policy](https://developer.spotify.com/policy)
- [OpenAI credential handling](https://developers.openai.com/api/reference/overview)
- [OpenAI structured output](https://developers.openai.com/api/docs/guides/structured-outputs)
- [Codex app-server and ChatGPT sign-in](https://learn.chatgpt.com/docs/app-server)
