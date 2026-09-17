# VibeCast

A native macOS menu bar companion for Spotify. Find a playlist for a mood, confirm it before playback, or use **Cast Magic** to create a private playlist from verified catalog tracks.

**Status: local subscription beta, not a public production service.** The Mac app supports each tester's own ChatGPT subscription through local Codex. A paid API or hosted AI service is not required for this beta. Spotify access approval, Apple signing, and live account acceptance tests remain necessary before distributing a public release.

**September 16, 2026 UI freeze:** the owner has approved the compact player, immersive miniplayer, lyrics/queue modes, and normal player controls. Preserve this UI checkpoint while reviewing the stacked PR and completing the next phase: request coverage, live playlist creation, friendlier errors, returning to suggestions after completed/declined requests, and developer-view acceptance. These request workflows are not declared complete. See [current status and next steps](docs/PROJECT_STATUS.md).

## The experience

- Playback controls, song search, and playlist search talk directly to Spotify.
- Every player progress bar supports hover highlighting, click-to-seek, and drag-to-seek with a local timestamp preview. A drag sends one guarded seek on release; seeking preserves the current play/pause state and queue.
- Successful player-button actions stay quiet in the normal view; failures and typed requests still get a response. Advanced history retains button diagnostics.
- Completed replies return to suggestions after one minute without interaction. Draft text, errors, unfinished playlists, pending confirmations, and open reading panels are preserved.
- The lyrics and queue buttons open their reading modes directly, with compact artwork/song/PiP headers and playback controls pinned below. The former intermediate pages and extra Lyrics Mode toggle are removed. Reopening lyrics for the current song reuses its in-memory result.
- Timed lyrics support click-to-seek. Both reading screens use ripple transitions in dropdown and pop-out presentations. Reading scrollbars are hidden, not scrolling itself.
- The lyrics-follow button floats over the bottom-right of the lyrics in both modes without reserving a row. Its circular sync icon uses the same active accent, inactive appearance, and hover treatment as the other player buttons.
- Lyrics begin near the top of the reading area. The highlight advances through the opening lines without scrolling until it reaches the center, then centered following takes over. Seeking back restores this opening layout in both lyrics modes.
- Pop out the same player into a movable, normal-level window; it is not always on top. The menu bar icon brings that window forward. Returning to the menu bar immediately opens the dropdown.
- On the experimental compact-dropdown branch, both dropdown and detached player use the same 340-point compact layout. Detached lyrics and queue modes resize vertically, with a 344-point minimum and independent remembered heights until redocking. Their dropdown versions retain the same fixed height. Other screens automatically fit their content. Switching containers preserves the selected panel, miniplayer, Advanced View, and draft. See [the experiment notes](docs/COMPACT_DROPDOWN_EXPERIMENT.md).
- Click album artwork to enter/exit the immersive miniplayer with a ripple transition. Playback, seeking, lyrics, queue, and Spotify device controls remain available. Immersive is the only miniplayer; the former Default layout and style setting have been removed, including their saved preference.
- Miniplayer uses edge-to-edge artwork with always-visible controls over a dark fade. Playback controls, the detached window's eight-dot drag grip, and the padded PiP corner are excluded from the artwork's exit-click area. Artwork color sampling and rendering stay local; no artwork or credentials are sent to AI for these effects.
- Miniplayer lyrics and queue open fixed-size reading screens over softly blurred artwork with a dark translucent veil. Their top-right lyrics/queue button ripples back to the miniplayer; artwork cannot exit while either screen is open. Both use the existing lyric and queue renderers. The current lyric has brighter contrast and subtle emphasis without changing its row geometry. The mini queue starts at Next Up, with Recently Played accessible through the same resisted pull and snap behavior as the normal queue. Normal reading screens remain independent. Stable ripple clips and shared decoded artwork avoid rebuilding content or flashing placeholders at transition endpoints, while both normal detached reading modes support vertical resizing.
- While the queue is open, Spotify playback is checked every two seconds. A detected track change reloads Up Next immediately, independently of the 12-second background queue refresh, including after confirmed player commands.
- Requests live on the landing screen (and in developer view), not on lyrics, queue, device picker, or miniplayer. Landing retains its VibeCast title and original spacing. Its three inspirations are Long Drive Night, Need to Focus, and Play Something Energetic, without trailing link arrows. It grows automatically for responses, long titles, and multiline input.
- Queue selections currently advance through intervening songs sequentially. Direct jumping while preserving the queue remains deferred; do not describe this as an atomic jump.
- Every playlist recommendation waits for **Sure!**. **Cast Magic** uses the original request to make a playlist.
- The same actions are available in the menu bar when notifications are disabled.
- Cast Magic generates a sequence of song titles and artists, matches them locally against real Spotify results, and creates a private playlist. It never trusts AI-generated Spotify IDs.
- Interrupted playlist population can resume without creating a second playlist.
- Right-click the menu-bar icon for **Advance Mode View**, **Settings**, **Quit VibeCast**, and **Contact Us!**. The footer has been removed; connection indicators now live below a separator in this menu. OpenAI status is shown only for the local ChatGPT subscription provider. Contact opens the default mail application addressed to `addarshshrivastava@gmail.com`, without sending a message. Developer view retains route/action/results, recent requests, and a copyable in-memory activity log. Settings remains an independent window.
- Settings edits remain pending until **Save changes**, which enables only for valid unsaved changes. Saving or reverting edits disables it again; a failed save preserves the draft. Account connect/disconnect and key removal remain immediate actions.

## Accounts and AI

Customers connect their own Spotify account using OAuth with PKCE. No Spotify client secret belongs in the app. Tokens are kept in Keychain, separately per app configuration. Spotify Premium is required for playback control.

Choose one AI connection in Settings:

- **ChatGPT subscription (beta default):** install Codex CLI, then use VibeCast's Sign in with ChatGPT button. Each tester uses their own subscription's Codex allowance. The app discovers available models from that account and never falls back to an API key or hosted service. See [subscription setup](docs/SUBSCRIPTION_BETA.md).
- **VibeCast service (optional future hosted experience):** customers need only Spotify sign-in. The included service exchanges Spotify authorization codes and issues short-lived VibeCast sessions. AI is billed separately to the publisher's API account, with persistent usage limits.
- **OpenAI API key (optional):** users explicitly supply their own separately billed API key. A ChatGPT subscription is not API credit.

The model receives the user's musical brief and shared curation instructions, not Spotify search results, artwork, account identifiers, or listening history. Subscription mode runs a private local Codex app-server process with isolated sign-in, ephemeral threads, execution/browser/plugin capabilities disabled, and read-only permissions. It does not invoke Computer Use or borrow the publisher's login. Musical quality still needs listening tests.

## Run locally

For everyday use, open **Applications > VibeCast**, or find VibeCast in Spotlight.
It is a menu bar app, so opening it adds the monochrome icon rather than a Dock window.
The installed app contains its own executable and resources; it does not need the
source checkout or Swift tools to launch. Subscription mode still needs Codex CLI.

Requires macOS 14+, a Swift 6 toolchain (Xcode 26 recommended for the glass UI), and Node 22.13+ for service tests. The wrapper handles the known incomplete Swift 6.4 Command Line Tools/macOS 27 SDK combination on this machine without changing system settings.

```sh
./script/build_and_run.sh --verify
./script/run_routing_checks.sh
./script/swift.sh test
(cd server && npm test)
```

The build/run command installs the development bundle in `/Applications/VibeCast.app`
and launches that copy. To install an already-built bundle without compiling, run
`./script/install_app.sh`. Set `VIBECAST_INSTALL_DIR="$HOME/Applications"` for a
user-only installation when the system Applications folder is not writable.
Launching from Finder or Spotlight never rebuilds or re-signs the app.

A fresh build opens disconnected. Configure Spotify in Settings > Advanced or use an ignored `Config/Local.plist` based on `Config/Local.example.plist`. Only the public client ID belongs in this file, never credentials.

In the Spotify developer dashboard register this **exact** redirect:

```text
http://127.0.0.1:43821/callback
```

Add beta testers to Spotify's allowlist. Then connect Spotify in VibeCast. Old prototype logins deliberately aren't migrated to the new bundle identity.

For local Cast Magic, enable the consent toggle, select **ChatGPT subscription**, and sign in. Leave the service address blank. Codex CLI 0.141.0 is the tested runtime; no API key is needed. To test the hosted path instead, follow [the service guide](server/README.md).

## Verification

Tests use isolated credentials and mocked HTTP/RPC services. They cover routing, confirmation-only playback, original-prompt handoff, notification failure, recommendation recovery, account binding, cancellation, current Spotify endpoints, private creation, resumable writes, OAuth validation, refresh coalescing, AI validation, server authentication, and usage limits. Subscription tests also cover ChatGPT-only authentication, unavailable allowance, no paid fallback, login rejection/cancellation, process crashes, timeouts, model discovery, and early completion events. They do not prove live account permissions or recommendation quality.

`VIBECAST_RENDER_UI=1 ./script/swift.sh test --filter VisualTests` renders light/dark screens to `.artifacts/previews` using local test data.

`VIBECAST_TEST_CODEX=1 ./script/swift.sh test --filter SubscriptionTests` additionally starts the installed runtime with a temporary, unauthenticated home. This smoke test does not sign in, generate music, or consume model usage.

`VIBECAST_TEST_PRESENTATION=1 ./script/swift.sh test --filter PresentationTests` checks native popover dismissal, anchoring during growth, fixed-height dropdown reading modes, preserved mode on detaching, selective resizing, and independent Settings presentation in an interactive macOS session. It briefly presents test windows. Automated geometry checks complement, rather than replace, live flicker testing.

## Distribution

Use [RELEASE.md](RELEASE.md) for build configuration, signing, notarization, a downloadable DMG, and launch prerequisites. The release script refuses an unconfigured or ad-hoc-signed public build.

Spotify's current [development mode](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) generally allows only five approved users. Its extended-access criteria currently target established organizations with at least 250k monthly active users. A normal downloadable app cannot remove those platform restrictions. Do not market this beta as unrestricted public Spotify access.

## Architecture

There is one shared `MenuBarRootView`, hosting controller, store, and presentation state. `MenuBarController` moves that existing hosting controller between the popover and the app window; it does not construct a second player. Features belong to the shared player, while the presentation layer owns dragging, dismissal, surface styling, anchoring, and resizing. Both presentations size their content against the height allocated by AppKit, preventing content from expanding ahead of the native surface.

```text
Menu bar / notification -> Store -> RequestRouter
  Playback / search ------------> Spotify Web API
  Find playlist ----------------> Persisted confirmation -> Spotify playback
  Cast Magic -> Local Codex + own ChatGPT OR hosted service OR personal API
             -> Local catalog matching -> private playlist -> resumable items write

OAuth browser -> loopback callback -> PKCE token exchange
  Hosted build: service validates client and user, issues VibeCast session
  Subscription/personal build without a service URL: Mac exchanges directly with Spotify
```

Pending recommendations expire after one hour. Partial playlist writes are retained for up to 24 hours. Disconnecting clears local account-specific state and notifications. Recent diagnostic history stays in memory.

See [the audit notes](docs/ARCHITECTURE_REVIEW.md) and [data handling](docs/PRIVACY.md).
