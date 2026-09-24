# Request Readiness: Owner QA

September 23, 2026. The implementation is ready for owner testing; **live acceptance is pending**. Automated fixtures and rendered previews do not establish Spotify behavior, account compatibility, notification delivery, or musical quality. Record each row as Pass, Fail, or Not exercised, and keep failures with their reproduction steps.

Direct playback from a clicked queue row is excluded. The approved player layout remains the regression baseline. This pass covers the existing feature set, not a player redesign or general-purpose chatbot.

## Prepare the installed candidate

1. Record the build commit, macOS version, Spotify app/device, and selected AI provider. Use the installed `/Applications/VibeCast.app` bundle for notification and Keychain checks.
2. Reconnect Spotify once. Creation recovery now needs **`playlist-read-private`** alongside private-playlist creation and playback permissions. An older login can still control playback but must reconnect before making or recovering a playlist.
3. Open Spotify on the intended Connect device. For subscription testing, connect your own ChatGPT account, check the displayed allowance, and select Account default or a model actually offered by the account.
4. Test the ordinary dropdown first, then repeat the marked interaction checks in the detached window. Open Adv when a result looks wrong; retain its route, original prompt, stage, outcome, resolved item, and sanitized activity log.

## Requests and conversation

| Check | Expected result | Owner result |
| --- | --- | --- |
| `pause`, `pause please`, `pause!`, `could you resume please?`, `pasue`, next/previous, shuffle on/off, repeat off/on/this song | Correct control. Typed requests wait for observed Spotify state; button successes stay quiet. Repeated clicks while busy do not duplicate a command. | Pending |
| `Play Peace of Blood by Citadelle`, `listen to Peace of Blood by Citadelle`, `put on "Animals" by Martin Garrix`, title-only form | Correct recording or useful clarification; same title/artist parsing across command forms. No false success while Spotify still plays another track/device. | Pending |
| A single misspelling with an explicit artist; a short or ambiguous title; live/remix/cover versions | Conservative matching. Unclear matches ask for more information or fail safely, rather than starting a different recording. | Pending |
| `queue Animals by Martin Garrix`, then an ambiguous title-only queue request and artist clarification | Adds the resolved song once without replacing playback. Queue confirmation means added to queue, not started playing. | Pending |
| `play songs by Martin Garrix`, `play some more by Ed Sheeran`, `play some EDM songs`, `late night driving` | Finds a playlist and waits for Sure. “Some more” is an artist-playlist request; it does not append an artist batch to the existing queue. | Pending |
| `what should I play?` → `jazz`; `I'm tired` → `acoustic`; `an artist` → artist name | Relevant local clarification with the conversational context carried into a playlist search. Nothing autoplays before Sure. | Pending |
| Unmatched `play [name]` → `artist`; repeat with `song` → performer | Follows the chosen interpretation; no incorrect playback during clarification. A new explicit command takes precedence over old context. | Pending |
| `play it`, bare `shuffle`, `don't play Animals`, a weather question, `never mind` | Clear bounded guidance, no guessed destructive or playback action. General questions are identified as outside the music assistant's capabilities. | Pending |
| Empty input, more than 600 characters, multi-line text, a fresh draft typed after a result | Sensible validation; no accidental submission or loss of the fresh draft. Dismiss and cancel clear clarification context. | Pending |

## Find, Sure, and notifications

| Check | Expected result | Owner result |
| --- | --- | --- |
| Find → Sure inline; then a fresh Find → Sure from macOS notification | The recommended playlist, context, and device are observed before success. Duplicate action activation sends no second playback command. | Pending |
| Find → dismiss; Find → Cast Magic inline and from notification after editing the composer | Dismiss restores suggestions while retaining new text. Cast Magic uses the recommendation's original brief, preserves new composer text, and does not autoplay. | Pending |
| Deny notification permission; turn notifications off in VibeCast; allow notifications again | Inline recommendation remains usable. Permission/delivery failures have concise feedback rather than losing the playlist. Verify actual banner actions from the installed bundle. | Pending |
| Relaunch with a pending recommendation; activate an expired or old-account notification | Valid recommendations remain actionable within their lifetime. Expired/foreign actions do not play anything and explain the problem. | Pending |
| Definite Spotify rejection versus a lost response/unconfirmed playback | A definite rejection permits an explicit retry. An uncertain Sure action stays consumed after relaunch; feedback says to check Spotify instead of replaying it automatically. | Pending |

## Cast Magic and recovery

| Check | Expected result | Owner result |
| --- | --- | --- |
| Consent disabled; disconnected subscription; unavailable model; expired Spotify login; old playlist scope | Clear recovery instructions before a playlist is created. A failed preflight preserves the original recommendation and its Sure action. | Pending |
| Real generation using ChatGPT subscription and two distinct musical briefs | Account/model/allowance shown correctly; no API fallback. Spotify receives a private playlist of real, distinct matched tracks. Inspect the reported count, privacy, suitability, and listening sequence. | Pending |
| Insufficient/unknown allowance or provider failure, when reproducible | No generation when allowance cannot be established; no switch to a paid provider. An unavailable test condition is Not exercised, not Pass. Do not consume allowance solely to force exhaustion. | Pending |
| Optional personal-key/hosted modes, if included in the release candidate | Test only the deliberately selected provider and its own credentials. Invalid keys/session, service failure, and quota errors are actionable; no cross-provider fallback. | Pending |
| Cancel during planning, Spotify matching, creation, and track writing; then submit a new request | No stale result overwrites the new request. Before creation there is no playlist. Once a write may have reached Spotify, recovery evidence remains available. | Pending |
| Interrupt the create response, then relaunch and use Check Spotify | Looks up the prior creation by its correlation marker; does not send a second create request. If found, it resumes and verifies the existing playlist. An incomplete/ambiguous lookup preserves recovery. | Pending |
| Interrupt adding tracks; choose Finish playlist; relaunch or reconnect before finishing | Reuses the same playlist. Success appears only after checking the saved tracks, order, owner, and privacy. No extra playlist is created by recovery. | Pending |
| Sign out with unfinished recovery; sign into a different account; return to the original account | The other account neither sees nor acts on the first account's recovery. Original recovery returns after reconnect, including after more than a day. | Pending |
| Dismiss an error with recovery present; Stop recovery → cancel; Stop recovery → confirm | Dismiss preserves recovery and draft. Confirmation explains that Spotify content is retained and a new request could duplicate it. Only explicit confirmation ends local tracking; an old dialog cannot clear a newer request. | Pending |

The Spotify description contains a small `[VibeCast:…]` correlation marker so an uncertain creation can be found safely. This marker contains a request UUID, not credentials. Do not remove it while creation recovery is pending. See [data handling](PRIVACY.md) for local recovery retention.

## Feedback and existing player regression

| Check | Expected result | Owner result |
| --- | --- | --- |
| Offline, timeout, rate limit, missing device, playback restriction, and authentication failure | Concise next steps; uncertainty is distinguished from definite rejection. Adv retains useful sanitized detail. Errors can be dismissed without erasing unfinished text. | Pending |
| Cancel, failure, success; inspect Adv; copy and clear logs | Original submitted prompt, final stage/outcome, and success/failure/cancellation history remain understandable. Copy uses the same redacted log as the screen. Clear log leaves current request/recovery intact. | Pending |
| Long error plus recovery; multi-line composer; dropdown and detached window | Text wraps in the scrollable request area. Dismiss/recovery actions remain reachable; the player and composer stay visible. Shared landing spacing returns after feedback/recovery ends. | Pending |
| Play/pause, previous/next, seek, shuffle/repeat, artwork and progress | Existing controls and visuals remain accepted. Seeking and previous reflect Spotify's actual permitted behavior; errors do not claim success. | Pending |
| Spotify Connect picker and typed device transfer; no devices; device disappears | Uses the selected Spotify device. Picker transfer preserves playing/paused state. Device failures are clear; macOS system audio outputs are not offered as Connect devices. | Pending |
| Lyrics consent, timed/plain/missing lyrics, song change, click-to-seek, manual scroll/follow | Consent respected, accurate fallback labels, highlighting follows playback, and stale lyrics do not survive a track change. | Pending |
| Queue/history display, refresh, scroll, track transitions | Accurate current queue and session history; scrolling/anchors remain stable. Do not test direct row jumping in this phase. | Pending |
| Dropdown ↔ detached, fullscreen/Spaces, status icon, lyrics/queue resizing, immersive mode | One shared player state; approved anchors, controls, bounds, composer draft, and panel selection remain intact. Repeat on the actual desktop rather than inferring acceptance from native fixture tests. | Pending |
| Settings save/cancel, Spotify/ChatGPT disconnect and reconnect, API-key removal | Unsaved settings do not apply. Connection controls affect their stated account; secrets stay in Keychain and approved request data follows the documented retention rules. | Pending |

## Record and close the pass

For each failure capture: **build, exact prompt/actions, initial Spotify state/device, expected result, actual result, final Adv stage/outcome, and whether it reproduces after relaunch**. Add a screenshot if it affects presentation. Never paste credentials; review copied logs before sharing. Record subjective playlist-quality feedback alongside functional failures.

The owner-use milestone can be signed off after the included live rows pass or any explicit scope exclusions are agreed, and the implementation is reviewed and merged. Keep outstanding items visible; do not label this document complete because automated tests pass.

Broad distribution is separate: Developer ID signing/notarization, clean-Mac installation and Keychain/notification checks, Spotify platform access, independent tester accounts, supported Codex runtime validation, and publisher privacy/support/release prerequisites still require their own evidence. See [release checklist](../RELEASE.md) and [subscription beta](SUBSCRIPTION_BETA.md).
