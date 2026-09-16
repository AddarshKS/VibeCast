# Compact Player Experiment

Branch: `codex/compact-dropdown-experiment`

Baseline: `97e97238b2d449ad9a5b52938d3dfc5e14f4d8cc` on `codex/public-beta`.
This is a player UI experiment, not a replacement for the accepted baseline or a change to request routing or Spotify playback commands.

## Scope

- Dropdown and detached player width: 340 points instead of 400. Settings retains its existing layout.
- Smaller outer insets, player artwork, typography, section gaps, and composer padding. The centered title sits above the player; PiP now sits beside the song details. Settings, quit, developer toggle, and connection status moved from header/footer to a native right-click menu, with Contact Us added. No playback controls were removed.
- Shared `PlayerDensity` environment controls layout only. `PlayerPresentation` selects the same compact metrics for both containers. No duplicate player implementation or separate playback state.
- Reading-panel body allocation: 300 points in both containers, capped by available screen height. Lyrics and queue use the space otherwise occupied by the composer; requests remain on landing and developer views only. Draft text is preserved across all mode changes. The composer has 14-point side insets and 16-point bottom clearance in the compact layout.
- Normal and focused lyrics use the same 18-point font in both containers. Scrolling, centering, seeking, and floating sync behavior are unchanged.
- Icon hit targets remain at least 28 points; the seek bar keeps its existing hit area and keyboard support.
- The native controller and shared view use one set of natural measurements across both containers. Resizing still happens before publishing the allocated content height, preserving the anti-flutter behavior.
- Only detached Lyrics Mode is manually resizable, down to 344 points, matching the two-row desktop widget reference. Landing, devices, developer view, queue, lyrics, and miniplayer are user-size-locked, while still automatically fitting content and the screen. Custom sizes reset on redocking, while panel, mode, and draft state survive.
- Album artwork toggles miniplayer in either container, including from focused lyrics. Exiting miniplayer returns to landing; its lyrics/queue/device buttons open their normal panels. The shared ripple originates at the clicked artwork. The title and suggestions/composer are omitted in this presentation.
- A shared artwork accent samples a 32-pixel thumbnail off the main actor. Miniplayer uses a 34%-opacity wash; the playback card uses a 30%-opacity fill above its material, consistent on landing, lyrics, and queue. Its bounded in-memory palette cache avoids repeated decoding. Missing artwork keeps a neutral mini background and the card's default teal tint. This does not invoke AI or change Spotify playback.
- Panel content crossfades without translating its scroll anchors; Reduce Motion uses shorter fades. Native sizing remains unanimated and top-anchored to avoid reintroducing the old dropdown flutter. Queue positioning happens during native layout, and the initial network refresh no longer performs a second scroll reset.
- The right-click menu uses a screen-coordinate anchor below the status icon, including on secondary displays. Local subscription status is restored at startup independently of Spotify, with a neutral checking state until the account is known. Visible menu status updates when the check or sign-out completes.
- Lyrics and queue headers no longer have redundant close buttons. Lyrics attribution sits beside the title; the plain "Try this!" hint, arrow, gap, and sparkle button share one uninterrupted hover region, while only the button is clickable. Refresh is the rightmost control; the separate floating lyric-sync button has extra bottom clearance.
- Queue includes up to five previously observed songs, oldest first, above Up Next. This is session-local history, not a full Spotify listening-history import: it requires no new scope, survives panel/container changes, and clears on logout or relaunch. Polls and shuffle/pause/seek changes do not add duplicates; confirmed track changes do. Opening and manual refresh reset to Up Next. New history rows preserve the upcoming viewport instead of moving it into history.
- Both lists share numbered song rows, spacing, artwork, durations (`--:--` when unavailable), and one guarded playback handler. Upcoming selections step forward; history selections step backward. Each step is device-bound and confirmed before continuing. A mismatch stops the operation, with no blind retry or playback-context replacement. History is locally observed, not an authoritative Spotify backward queue, so this remains provisional pending the deferred direct-jump work.
- A narrow AppKit scroll marker uses the measured Up Next header as its anchor. Browsing within Up Next remains native. Pulling upward from Up Next or downward from Recently Played has matching 0.30 resistance and a 90-point threshold; releasing early returns to the originating section. Passing the threshold snaps to the other section with a 260ms ease-out. Fast scrolling from deeper in Up Next stops at its heading and requires a fresh pull to reveal history. Stops within 36 points of Up Next snap to it. Momentum alone cannot change sections; Reduce Motion disables snap animation. The marker and local event monitor are detached with the view.
- Settings activates again after menu tracking ends and accepts activation clicks, including through SwiftUI on macOS 15+. Its close button uses the shared hover style. The request field now reads "Let's cast your vibe!", starts unfocused, and leaves editing when another control is clicked or its window resigns key status.
- The composer has a clearer neutral border when idle, a teal border while editing, and brighter text with a left-to-right glow sweep on hover. Lyrics Mode uses a pulsing hover glow across the continuous hint-to-button hover area only before entering the mode; while active, its button keeps the standard steady teal highlight, including on hover. Both clocks exist only while hovered, run at most 30fps, respect Reduce Motion, and do not change layout or focus.

With the local playback fixture, landing measures 340 x 418 points, miniplayer 340 x 384, and lyrics/queue 340 x 544. Content can still grow for long titles, multiline input, recommendations, errors, and developer logs.

## Verification

- Automated coverage includes subscription restoration without opening Settings, live menu status updates, chronological bounded history, queue scroll restoration with an empty upcoming list in both containers, history growth without a viewport jump, pull/snap boundaries, shared forward/backward confirmation guards, and initial composer focus. Native tests additionally check Settings activation and first-mouse acceptance. Physical trackpad feel and real Spotify history stepping still require manual acceptance.
- Render light/dark player, lyrics, focused lyrics, queue, device picker, recommendation, onboarding, and developer states with `VIBECAST_RENDER_UI=1 ./script/swift.sh test --jobs 2`.
- Run native anchoring, dismissal, shared-host/state, and resizing tests with `VIBECAST_TEST_PRESENTATION=1 ./script/swift.sh test --jobs 2 --filter PresentationTests`.
- The suite checks long-title/multiline-request geometry, composer visibility rules, native menu order and conditional connection indicators, artwork palette extraction, and selective resizing. Native tests assert equal natural sizes on detachment and preserve the same hosting controller, modes, and draft through repeated miniplayer and Lyrics Mode round trips.
- Compare dropdown and pop-out manually, including long titles and requests, scrolling/seeking lyrics, entering/exiting Lyrics Mode, and returning to the dropdown from a resized window.
- Offscreen snapshots and native geometry tests do not replace checking perceived flicker and compositor effects on the actual desktop.

## Returning To The Baseline

Keep or stash experimental edits before switching branches. Switching back to `codex/public-beta` and rebuilding/installing restores the accepted design. Merely changing branches does not replace an already installed app. No changes to the original branch or its PR are required to try this experiment.
