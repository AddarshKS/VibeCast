# Release VibeCast

## Current readiness

The beta app builds and launches locally. Automated tests exercise the integration boundaries with mock services. This is not yet a live, signed public release.

As of September 16, 2026, the owner has accepted the player UI/UX, dropdown/pop-out behavior, Lyrics Mode, and normal controls. Request completion is a separate remaining milestone: full prompt coverage, live playlist creation, error presentation, completion/decline cleanup, and Advanced View testing. See [PROJECT_STATUS.md](docs/PROJECT_STATUS.md). Do not treat UI acceptance as public-release readiness.

There are four operator prerequisites that code cannot provision automatically:

1. **Spotify access.** Configure the Spotify app and exact callback, allowlist beta testers, and obtain approval before unrestricted public distribution. Current extended-access requirements include a registered organization and at least 250k MAUs. See [Spotify quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).
2. **AI delivery.** The subscription beta requires each tester to install Codex CLI and connect their own ChatGPT account. No hosted service or API key is required. For a later hosted experience, deploy the included service over HTTPS with a server-only OpenAI API key, persistent volume, budget, and allowlist. Customers would then need only Spotify sign-in.
3. **Apple trust.** Install your Developer ID Application signing certificate and configure a notarytool keychain profile. This machine currently has no signing identity.
4. **Live acceptance.** Run the Spotify and AI tests below using real accounts. Automated mocks do not establish token permissions, live playlist creation, or musical quality.

## Configure the artifact

For a subscription beta, create an ignored `Config/Release.plist` from `Config/Local.example.plist`: set the public Spotify client ID, keep the service URL empty, and keep `VibeCastAIProvider` set to `chatGPT`. For hosted distribution, use `Config/Release.example.plist` with provider `hosted` and your HTTPS service origin. Never put an OpenAI key, Spotify secret, tokens, or personal account identifiers into either file.

The app identity is `app.vibecast.mac`; development uses `app.vibecast.mac.development`. These identities are separate from the old prototype, preventing shared notification routing and old Keychain access prompts. Keep the release identity and signing team stable between updates.

Register this callback with Spotify:

```text
http://127.0.0.1:43821/callback
```

The callback listener binds only to IPv4 loopback, checks OAuth state, limits HTTP header size, times out, and serves a completion page. It uses no custom URL scheme or LaunchServices callback registration.

## Build the download

```sh
export VIBECAST_CONFIG="$PWD/Config/Release.plist"
export VIBECAST_CODE_SIGN_IDENTITY="Developer ID Application: YOUR LEGAL NAME (TEAMID)"
export VIBECAST_NOTARY_PROFILE="your-notarytool-profile"
./script/release.sh
```

The script runs tests, builds optimized code, assembles resources and icon, signs with hardened runtime, notarizes and staples the app, verifies Gatekeeper, creates a DMG with an Applications shortcut, and notarizes/staples the DMG.

Output: `dist/VibeCast-0.2.0-arm64.dmg` on Apple Silicon or `...-x86_64.dmg` on Intel. This pipeline currently produces the host architecture, not a universal binary. Do not advertise Intel support without building and smoke-testing that artifact on Intel.

Increment `CFBundleShortVersionString` and `CFBundleVersion` in `Config/Info.plist` for subsequent releases.

## Local development

`./script/build_and_run.sh --verify` produces a development app in `dist/VibeCast.app`, installs it in `/Applications/VibeCast.app`, and launches the installed copy. `./script/install_app.sh` installs an already-built development bundle without compiling. Use `VIBECAST_INSTALL_DIR="$HOME/Applications"` if needed. The installer refuses to overwrite a different edition and stops only the source/destination executables.

Local builds are ad-hoc signed unless `VIBECAST_CODE_SIGN_IDENTITY` specifies an installed signing identity. This is for local testing, not a downloadable public release. The same signing variable supports a stable Apple Development identity for development; public downloads require Developer ID and notarization as above.

The package script stages the app before replacing the previous generated bundle. The installer stages and verifies the new copy before replacing the installed development app. No prototype source folder or differently identified installed app is removed.

### Keychain prompts

An ad-hoc signature's designated requirement is tied to the specific executable. After code changes, Keychain may treat the rebuilt app as a different requester. Copying the unchanged bundle does not create a new code signature. Opening the installed app from Finder avoids accidental rebuilding, but does not fix signing identity changes during development.

For the trusted installed build, **Always Allow** remembers access to that Keychain item; **Allow** approves only the current request. A later ad-hoc rebuild can ask again even after Always Allow. Multiple item accesses or a token read followed by a refresh write can produce more than one prompt. Never remove Keychain protections or store tokens in plaintext to hide these dialogs.

For public releases, keep the bundle identifier and Developer ID signing identity/designated requirement consistent across updates, sign with hardened runtime, and notarize. Each user's tokens live in their own Mac's Keychain, not in the downloadable app. Normal relaunches and correctly signed updates should not repeatedly ask for Keychain approval. A locked Keychain, changed trust settings, or a signing-channel change can still require authorization; zero prompts under all conditions is not a guarantee. The macOS password is entered into the system dialog, not VibeCast. The subscription beta's external Codex runtime manages its own separate Keychain authorization.

References: [Apple on designated requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Apple on Allow versus Always Allow](https://support.apple.com/guide/keychain-access/if-youre-asked-for-access-to-your-keychain-kyca1243/mac).

## Acceptance tests

Start with the owner's Spotify account; a second Premium account is not a blocker to local testing. Before sharing broadly, repeat these checks with at least two independent, allowlisted Spotify accounts and separate ChatGPT accounts.

- Fresh install: connect each account, verify browser completion, relaunch, and refresh an expired token.
- `play some EDM songs`: recommendation and both actions; no playback before Sure.
- Deny notifications: recommendation still works from the menu.
- Quit/reopen after receiving a recommendation: Sure resumes the correct request, and double-clicks don't execute twice.
- `play songs by Ed Sheeran`: artist playlist, not a track called Songs.
- `make me a soft rock playlist`: private playlist, at least eight verified tracks, sensible selection and sequence.
- Subscription beta: sign in from VibeCast, confirm account/model/allowance, relaunch, generate a playlist, cancel another request, and disconnect. Verify the main Codex app's login is unchanged. Missing/exhausted allowance must stop generation, with no paid fallback.
- Cast Magic from a notification: retain the original prompt even after typing a new one.
- Interrupt the items write: finish the same playlist rather than creating a duplicate.
- Disconnect/reconnect as another account: old recommendations and partial writes aren't usable.
- No active Spotify device, no Premium, unavailable songs, service offline, AI limit reached, and expired sessions all produce useful outcomes.
- Verify light/dark mode, long playlist titles, larger text settings, keyboard navigation, VoiceOver names, and notification action delivery on a signed build.
- Player: open/close Lyrics and Up next, scroll each, change songs, pause/resume, seek forward/backward in Spotify, reopen the popover, and submit a request while a panel is selected. Timed LRCLIB lyrics should highlight and scroll to the current line; manual scrolling suspends following on macOS 15+, and the follow button resumes it. macOS 14 uses the explicit follow/pause button. Test plain-text fallback, instrumental, missing lyrics and offline playback. Timing quality depends on provider data and Spotify position updates. Verify provider attribution, privacy disclosure and suitability of lyrics licensing/terms before public distribution; this integration alone does not establish redistribution rights.
- Devices: switch between two Spotify Connect devices, including while paused. Restricted or disappeared devices must not transfer; same-named devices must use exact IDs. System audio settings must not change.
- Shared player: enter Lyrics Mode from the dropdown; the ripple must not change its native height. Pop out while focused, verify mode and playback are retained, then resize vertically. Width must remain fixed. Normal lyrics and queue lock window height; closing either restores the prior standard height. Redocking opens the dropdown and resets custom dimensions/focus. The detached window must remain normal-level, and the menu bar icon must bring it forward.
- Dropdown transitions: repeatedly go from suggestions to queue or lyrics, between reading panels, and back. Check for flicker or anchor movement on desktop and in fullscreen with an auto-hiding menu bar. Clicking Volume/Wi-Fi/other status icons, outside the dropdown, or VibeCast again must dismiss it; detached windows must not inherit that dismissal.
- Queue selection: the accepted interim implementation advances through intervening tracks, with confirmation/cancellation guards. Test this without expecting an atomic jump or replacing the Spotify playback context. Direct-jump research remains deferred.
- Request cleanup (remaining work): accepted, declined, cancelled, and failed requests must each have a clear route back to suggestions without losing diagnostics, fresh drafts, or recoverable playlist work. The current error-preserving idle policy does not yet satisfy this target.
- Advanced View (remaining acceptance): verify route/action/resolved item, original prompt, pending recommendation, timestamped history, failure stage, copy/clear log controls, and account cleanup for both successful and unsuccessful requests. Normal-view cleanup must not erase the developer evidence needed to reproduce a failure.
- Adaptive panel: short status/error messages should shrink the menu; queue, lyrics, long requests and diagnostics grow it only to the screen-height cap. Input and footer remain visible, with longer content scrolling. Check a mixed track/podcast queue and an empty queue.
- Settings: drag its title, edit fields, close with the internal X or Escape, then reopen. There must be no duplicate native title bar or three-dot menu.
- Check the downloaded, quarantined DMG on a clean Mac without the repo, Swift tools, or any publisher credentials. For subscription builds, test the missing-Codex message, install Codex, then sign in with that tester's own account. Hosted builds must work without Codex installed.

## Website and operations

Host only the **notarized** DMG on your website or a release/CDN endpoint over HTTPS. Show version, minimum macOS version, architecture, checksum, support contact, and actual beta access conditions. Publish a privacy policy with your real operator identity and contact address using [the data inventory](docs/PRIVACY.md). Do not link a nonexistent service or claim Spotify approval.

No auto-updater or payment system is included. The initial beta uses manual replacement updates. Add a signed update feed only once the hosting and release-signing setup is stable.

Monitor health and aggregate quota errors without logging prompts, bearer tokens, or Spotify content. Keep database persistence and OpenAI project spending controls enabled. Recheck Spotify policies before public launch; technical compatibility alone does not establish platform approval.
