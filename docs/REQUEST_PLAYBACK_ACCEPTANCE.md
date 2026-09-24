# Request Playback Confirmation

September 23, 2026. First request milestone on `codex/request-playback-confirmation`, based on `main` at `2d92c0f`. The approved player views, native containers, and queue-navigation behavior are unchanged.

## Implemented contract

- Typed playback controls and exact-song requests remain in progress until observed Spotify playback matches the requested state on the selected device. Song requests retain the resolved track URI through dispatch and confirmation.
- Sure uses the same confirmation path from the inline card and notification. It requires playing state, the selected device ID, and the recommended playlist's context URI. Spotify's [playback-state response](https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback) supplies this optional context; absent or mismatched context cannot confirm a playlist.
- Confirmation performs at most six player reads with the existing delay between attempts. It never resends the playback command. Existing HTTP authentication refresh handling remains in the Spotify client.
- A fresh player read establishes the baseline. Requests pin the selected Spotify Connect device through the write and confirmation; named transfers keep that ID even if another same-named device appears.
- Background polls cannot overwrite a pending or freshly confirmed request with an older response. Cancellation and logout prevent late work from publishing success.
- Definite rejections allow an explicit Sure retry. If the write outcome is uncertain, the player cannot be read afterward, or confirmation times out, the recommendation remains consumed, including after relaunch. Feedback tells the user to check Spotify before trying again.
- Existing Adv fields/logs record resolving, preflight, dispatch, confirmation, and outcome. Transport failures record safe error codes rather than raw error URLs or payloads. History retains the submitted brief even after the draft changes.
- Queue requests still acknowledge queueing without waiting for that song to play. Find requests still await Sure. Cast Magic retains the original brief and does not start playback. Player-button successes remain quiet.

## Acceptance matrix

Automated fixtures cover the cases below. Live owner acceptance is pending; fixture success does not establish real Spotify behavior or musical quality.

| Case | Expected result | Live status |
| --- | --- | --- |
| `Play Peace of Blood by Citadelle`, then the title-only form | Matching song and device observed before success; useful no-match feedback otherwise | Pending |
| `pause`, `resume`, `next`, `previous`, shuffle and repeat commands | Observed requested state; delayed reads keep progress visible; a timeout sends no second command | Pending |
| `play some EDM songs`, `late night driving`, `play songs by Ed Sheeran` | Recommendation only; no playback before Sure | Pending |
| Sure inline and from a notification | Expected playlist context and device observed; repeated activation dispatches once | Pending |
| Decline a recommendation | Inspirations return, with a fresh draft and diagnostic history retained | Pending |
| Cast Magic from a notification after editing the composer | Original recommendation brief reaches the planner; new draft survives | Pending; live creation and quality are a separate milestone |
| `what should I play?`, `damn I'm tired` | Conversation response without playback | Pending |
| No matching track or available device | Actionable error and no playback write | Pending |
| Explicit Spotify rejection, expired login, or rate limit | Actionable feedback and Adv evidence; no automatic command resend | Pending |
| Wrong track/context/device, paused playlist, or absent player state | No playback success; bounded confirmation failure | Pending |
| Lost write response or unavailable confirmation read | Uncertain-outcome feedback; old Sure action cannot replay, including after relaunch | Pending |
| Cancel during preflight or confirmation, then submit another request or log out | No stale completion or state overwrite; cancellation before dispatch sends no command | Pending |

For a live pass, record the prompt, route, resolved item, Adv stage/outcome, and actual Spotify state. Confirm the visible feedback in both dropdown and detached containers without changing their layout. Do not simulate a direct queue jump or run playlist-creation tests as part of this playback-only pass.

## Automated verification

Use `script/swift.sh` for Swift commands and run them sequentially. Focused request, routing, store, service, feedback, and confirmation tests passed (70 tests in six suites). The full rendering run passed 201 tests across 20 suites; routing-only checks passed four cases; the optional service passed nine tests. All 26 native presentation tests passed on the third unchanged run. `PROJECT_STATUS.md` retains the earlier intermittent native failures and the untouched-main comparison. Detailed local logs are ignored under `.artifacts/request-playback`.

Live subscription allowance/generation, playlist matching quality, interrupted creation recovery, broader routing, and cancellation/error dismissal design remain separate work.
