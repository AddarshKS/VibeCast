# VibeCast Data Handling

This is an engineering data inventory for the future publisher, not a published privacy policy. Before distribution add the actual operator identity, support contact, hosting region, processors, retention obligations, and any legally required terms.

## On the Mac

- Spotify access/refresh tokens and optional personal OpenAI API key: macOS Keychain, device-local accessibility.
- Connection settings and AI consent: UserDefaults.
- ChatGPT subscription credentials: managed by Codex in macOS Keychain, scoped to VibeCast's isolated Codex home, separate from the user's main Codex login. VibeCast reads account email/plan and remaining allowance to display connection status; it does not read OAuth tokens itself.
- Pending recommendations: original request, selected playlist metadata, account ID, status, creation time. Used to resume notifications, limited to ten entries, actionable for one hour.
- An unfinished newly created playlist and its verified tracks: recoverable for up to 24 hours. Expired records are purged on the next app launch/account restore or recovery action, not by a background service while the app is closed.
- Recent diagnostic history: memory only, up to eight requests. Activity log: up to 100 in-memory stage/status/error entries, including selected playlist names and search phrases. OAuth codes, tokens, browser auth URLs, and API keys are not logged. Copying the log is an explicit user action; review it before sharing.
- Displayed Spotify artwork: loaded from the provided Spotify image URL.
- Player queue: fetched from Spotify only while the queue panel is visible; retained in memory and cleared on Spotify disconnect.
- Optional lyrics: disabled by default. Enabling LRCLIB shares the current song title, first artist, album name and duration with `https://lrclib.net/api/get` while the lyrics panel is open. No Spotify tokens, account IDs, listening history or AI credentials are attached. Lyrics are held in memory, not written to disk. Requests use a cookie-free ephemeral session. LRCLIB receives the user's IP address and its own processing policies apply. Disable in Settings > Lyrics. When timed lyrics exist, line highlighting and scrolling use Spotify's playback position, refreshed every two seconds while that panel is visible and interpolated locally between responses. Plain lyrics are a labeled fallback; no AI-generated lyrics or fabricated timings are used.
- The speaker picker lists Spotify Connect devices. Selecting one transfers playback to its exact Spotify device ID while preserving the playing/paused state. It does not enumerate or change macOS system audio outputs.
- Disconnect Spotify clears Spotify-specific pending data, unfinished state, displayed history, tokens and notifications. Disconnect ChatGPT separately logs out VibeCast's local Codex connection. The optional personal OpenAI key has its own Remove saved key command.

Expired recommendation records are purged on the next app launch. Data already included in the user's system backups is governed by their backup retention settings.

## Hosted mode

The Mac sends the PKCE authorization code/verifier or refresh token to the configured VibeCast service over HTTPS. The service exchanges it with Spotify, checks the beta allowlist, and returns the Spotify tokens plus a VibeCast session. Spotify credentials are not persisted server-side.

The service database stores session hashes, pseudonymous account identifiers, expirations, and quota counters. Expired entries are removed on subsequent session/quota operations. Sessions last at most one hour; counters last for their rate-limit window. Production operators should also schedule database maintenance if the service becomes inactive.

The service sends only the user's musical request to OpenAI with response storage disabled. It does not send Spotify search results, artwork, credentials, playback history, profile data, or account identity to OpenAI. OpenAI's own API processing and retention terms still apply; disabling response storage does not promise zero retention by the provider.

## Personal-key mode

The user's musical request goes directly from the Mac to OpenAI using the key explicitly saved by the user. That key is never sent to the VibeCast service. Model responses are interpreted only as proposed song titles and artists, then verified locally using Spotify search.

## ChatGPT subscription mode

VibeCast launches the installed Codex CLI's app-server locally over stdio, not a public network listener. `CODEX_HOME` points to `~/Library/Application Support/<bundle-id>/Codex`, separating Codex configuration and authentication from the user's normal Codex home. `HOME` retains the real macOS user directory so the system can locate the login Keychain; replacing it breaks credential persistence. Inherited environment variables are restricted; API credentials are not passed to the process. Browser sign-in belongs to the tester's own ChatGPT account.

The app sends the musical request, shared curator instructions, and an output schema. Spotify catalog results and credentials are never included. Threads are ephemeral and Codex history persistence, analytics, and feedback are disabled. Codex may still maintain runtime state or diagnostics in its isolated home. These local settings do not promise zero retention by OpenAI; ChatGPT/Codex account data controls and provider terms apply, rather than the separate API mode's `store: false` setting.

Command, browser, computer-use, plugin, and MCP capabilities are disabled for this integration. Requests use a read-only sandbox, never grant tool approvals, and reject incoming execution requests. The tested runtime does not support a blanket tool-disable switch or a restricted read-root setting; read-only is not complete filesystem isolation. This is a local beta integration for the signed-in person's own musical prompts, not a public remote execution endpoint. Do not expose it through a network service or feed it external instructions. Review capability changes when upgrading the tested Codex runtime.

## Operational requirements

- Publish data sharing before asking for AI consent.
- Use HTTPS and keep API keys out of the distributed app, analytics, crash reports and logs.
- Do not enable raw HTTP/body/Authorization logging at the hosting proxy.
- Keep any private database backups access-controlled and define a deletion policy.
- No analytics, advertising, computer-use access, or prompt collection is included in this implementation.
- Spotify data must be handled in accordance with [Spotify's policies](https://developer.spotify.com/policy).
