import AppKit
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
@Suite(.serialized)
struct VisualTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func queueHeaderStaysAlignedThroughoutOpeningAndRefresh() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        for index in 0..<6 {
            api.playbackValue = SpotifyPlayback(isPlaying: true,
                item: SpotifyTrack(uri: "spotify:track:h\(index)", name: "History \(index)",
                                   artists: [], album: nil, isPlayable: true),
                device: nil, shuffleState: false, repeatState: "off")
            await store.refreshPlayback()
        }
        for detached in [false, true] {
            let state = PlayerPresentation()
            state.isDetached = detached
            state.windowHeight = 544
            let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
            host.sizingOptions = []
            host.safeAreaRegions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 544),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            try await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.2)) { state.selectPanel(.queue) }
            var samples = 0
            for _ in 0..<25 {
                try await Task.sleep(for: .milliseconds(16))
                host.layoutSubtreeIfNeeded()
                if let marker = queueMarker(in: host), let scroll = marker.enclosingScrollView,
                   let document = scroll.documentView {
                    let anchor = marker.convert(marker.bounds, to: document).minY
                    #expect(abs(anchor - scroll.contentView.bounds.minY) < 1,
                            "Up Next must start and remain at its final snapped position during the opening fade.")
                    samples += 1
                }
            }
            #expect(samples > 15)
        }
    }

    private func queueMarker(in view: NSView) -> QueueScrollBehavior.Marker? {
        if let marker = view as? QueueScrollBehavior.Marker { return marker }
        return view.subviews.lazy.compactMap { queueMarker(in: $0) }.first
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func growingHistoryPreservesUpcomingPositionAndNeverFocusesComposerOnOpen() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let state = PlayerPresentation()
        state.windowHeight = 544
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 544),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!(window.firstResponder is NSTextView), "Opening the player must not start editing the request.")
        state.selectPanel(.queue)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(scrollViews(in: host).first)
        var previousOffset: CGFloat = 0
        for index in 0...6 {
            api.playbackValue = SpotifyPlayback(isPlaying: true,
                item: SpotifyTrack(uri: "spotify:track:n\(index)", name: "Song \(index)", artists: [], album: nil, isPlayable: true),
                device: nil, shuffleState: false, repeatState: "off")
            await store.refreshPlayback()
            try await Task.sleep(for: .milliseconds(120))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            let offset = scroll.contentView.bounds.minY
            if index > 0 && index <= 5 { #expect(offset > previousOffset + 30, "New history must stay above Up Next, not move into view.") }
            if index == 6 { #expect(abs(offset - previousOffset) < 1, "Rolling five-song history must not move the viewport.") }
            previousOffset = offset
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func queueOpensBelowHistoryEvenWithNoUpcomingSongsAndResetsOnReopen() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        for index in 1...6 {
            api.playbackValue = SpotifyPlayback(isPlaying: true,
                item: SpotifyTrack(uri: "spotify:track:\(index)", name: "History song \(index)",
                                   artists: [.init(name: "Test Artist")], album: nil, isPlayable: true),
                device: nil, shuffleState: false, repeatState: "off")
            await store.refreshPlayback()
        }
        #expect(store.playerDetails.recentlyPlayed.count == 5)
        for detached in [false, true] {
            let state = PlayerPresentation()
            state.isDetached = detached
            state.selectPanel(.queue)
            state.windowHeight = 544
            let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
            host.sizingOptions = []
            host.safeAreaRegions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 544),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let scroll = try #require(scrollViews(in: host).first)
            #expect(scroll.contentView.bounds.minY > 200, "History must start above the viewport, even for an empty Up Next list.")
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(scroll.contentView.bounds.minY < 1)
            state.selectPanel(nil)
            try await Task.sleep(for: .milliseconds(100))
            state.selectPanel(.queue)
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let reopened = try #require(scrollViews(in: host).first)
            #expect(reopened.contentView.bounds.minY > 200, "Reopening must return to Up Next, not the previous history position.")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func compactLandingKeepsPlayerAndComposerVisibleAtItsFixedHeight() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let track = SpotifyTrack(uri: "spotify:track:test", name: "A Very Long Evening Song Title That Wraps Across Two Lines",
                                 artists: [.init(name: "The Test Band")], album: nil, isPlayable: true, durationMS: 213000)
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: track, device: nil,
                                           shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let state = PlayerPresentation()
        state.isDetached = true
        let landingHeight: CGFloat = 418
        state.windowHeight = landingHeight
        var sections: [String: CGFloat] = [:]
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state)
            .onPreferenceChange(PanelMeasurements.self) { sections = $0 })
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PlayerPresentation.width,
                                                  height: landingHeight),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for prompt in ["", "Find me something calm for tonight\nWith acoustic guitars and soft vocals\nAnd a little instrumental piano"] {
            store.prompt = prompt
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let top = try #require(sections["top"])
            let bottom = try #require(sections["bottom"])
            #expect(top + bottom + 20 <= landingHeight,
                    "The player, multiline composer, and a scrollable response area must fit the fixed landing window.")
            #expect(host.bounds.width == 340)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func lyricsStartAtTopThenFollowTheCenterAndResetAfterSeekingBack() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let lyrics = try #require(TimedLyrics(lrc: (0..<12).map {
            String(format: "[00:%02d.00]Lyric line %d", $0 * 4, $0 + 1)
        }.joined(separator: "\n")))
        func position(_ milliseconds: Int) async {
            api.playbackValue = SpotifyPlayback(isPlaying: false, item: PlayerTests.track,
                device: SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
                shuffleState: false, repeatState: "off", progressMS: milliseconds)
            await store.refreshPlayback()
        }
        await position(0)
        for height in [220.0, 420] {
            let host = NSHostingView(rootView:
                SyncedLyricsView(store: store, lyrics: lyrics, trackURI: PlayerTests.track.uri, height: height))
            host.sizingOptions = []
            host.safeAreaRegions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            await position(0)
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded()
            let scroll = try #require(scrollViews(in: host).first)
            #expect(abs(scroll.documentVisibleRect.minY) < 1, "Opening lyrics must not scroll or leave a centered first line.")
            await position(4000)
            try await Task.sleep(for: .milliseconds(600))
            #expect(abs(scroll.documentVisibleRect.minY) < 1, "The highlight should move through opening lines without scrolling.")
            await position(32000)
            try await Task.sleep(for: .milliseconds(600))
            let laterOffset = scroll.documentVisibleRect.minY
            #expect(laterOffset > 100, "Later lyrics should resume centered following.")
            await position(44000)
            try await Task.sleep(for: .milliseconds(600))
            #expect(scroll.documentVisibleRect.minY > laterOffset + 80,
                    "Bottom padding must allow even the final line to follow the center.")
            await position(0)
            try await Task.sleep(for: .milliseconds(600))
            #expect(abs(scroll.documentVisibleRect.minY) < 1, "Seeking back must restore the top-aligned opening.")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func normalLyricsAndFloatingControlFitInsideAllocatedReadingViewport() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture(lyrics: PreviewTimedLyrics())
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: false, repeatState: "off", progressMS: 74000)
        await store.refreshPlayback()
        store.settings.lyricsEnabled = true
        await store.playerDetails.loadLyrics(for: PlayerTests.track, enabled: true)
        let state = PlayerPresentation()
        state.selectPanel(.lyrics)
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 680),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for detached in [false, true] {
            state.isDetached = detached
            let density = PlayerPresentation.density
            for height in [500.0, 550, 680] {
                state.windowHeight = height
                window.setContentSize(NSSize(width: density.width, height: height))
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let scrolls = scrollViews(in: host)
                let outer = try #require(scrolls.first)
                let document = try #require(outer.documentView)
                #expect(document.frame.height <= outer.contentView.bounds.height + 1,
                        "The floating sync control must fit inside the lyrics panel at height \(height).")
                let lyricsScroll = try #require(scrolls.dropFirst().first)
                let allocatedLyricsHeight = max(0, outer.contentView.bounds.height - density.lyricsReserve)
                #expect(abs(lyricsScroll.frame.height - allocatedLyricsHeight) < 1,
                        "Lyrics must use the full allocated height, with no reserved sync-button row.")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func renderCompactAndFocusedLyrics() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".artifacts/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (store, api, _, _, _) = try await StoreTests().fixture(lyrics: PreviewTimedLyrics())
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device:
            SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: true, repeatState: "off", progressMS: 74000)
        await store.refreshPlayback()
        store.settings.lyricsEnabled = true
        await store.playerDetails.loadLyrics(for: PlayerTests.track, enabled: true)
        let state = PlayerPresentation()
        state.isDetached = true
        state.recordResize(390)
        try await render(MenuBarRootView(store: store, presentation: state), name: "compact-player-dark",
                         directory: output, scheme: .dark, height: 390)
        state.selectPanel(.lyrics)
        state.windowHeight = 574
        for scheme in [ColorScheme.dark, .light] {
            try await render(MenuBarRootView(store: store, presentation: state),
                             name: "detached-lyrics-hint-\(scheme)", directory: output,
                             scheme: scheme, height: 574)
        }
        state.toggleLyricsFocus()
        for height in [344.0, 390, 650] {
            state.recordResize(height)
            try await render(MenuBarRootView(store: store, presentation: state), name: "focused-lyrics-\(Int(height))-dark",
                             directory: output, scheme: .dark, height: height)
        }
        try await render(MenuBarRootView(store: store, presentation: state), name: "focused-lyrics-light",
                         directory: output, scheme: .light, height: 650)
        state.isDetached = false
        state.resetWindowSize()
        state.selectPanel(.lyrics)
        state.windowHeight = 550
        for scheme in [ColorScheme.dark, .light] {
            try await render(MenuBarRootView(store: store, presentation: state),
                             name: "popover-lyrics-\(scheme)", directory: output, scheme: scheme, height: 550)
            state.toggleLyricsFocus()
            try await render(MenuBarRootView(store: store, presentation: state),
                             name: "popover-focused-lyrics-\(scheme)", directory: output, scheme: scheme, height: 550)
            state.toggleLyricsFocus()
        }
        api.playbackValue = SpotifyPlayback(isPlaying: false, item: PlayerTests.track, device:
            SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: false, repeatState: "off", progressMS: 0)
        await store.refreshPlayback()
        try await render(MenuBarRootView(store: store, presentation: state), name: "lyrics-song-start-dark",
                         directory: output, scheme: .dark, height: 550)
        state.toggleLyricsFocus()
        try await render(MenuBarRootView(store: store, presentation: state), name: "focused-lyrics-song-start-dark",
                         directory: output, scheme: .dark, height: 550)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func dropdownContentWaitsForNativeHeightBeforeExpanding() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                           shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let state = PlayerPresentation()
        state.windowHeight = 420
        var requestedHeight: CGFloat = 0
        let host = NSHostingView(rootView: MenuBarRootView(store: store, resize: { requestedHeight = $0 }, presentation: state))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(100))
        let outer = try #require(scrollViews(in: host).first)
        let originalHeight = outer.frame.height
        for panel in [PlayerPanel.queue, .lyrics] {
            state.selectPanel(panel)
            try await Task.sleep(for: .milliseconds(100))
            #expect(requestedHeight > 420)
            #expect(outer.frame.height <= originalHeight + 61,
                    "Before native resizing, detail content can reclaim the 60pt composer but must not outgrow the surface.")
            window.setContentSize(NSSize(width: 340, height: requestedHeight))
            state.windowHeight = requestedHeight
            try await Task.sleep(for: .milliseconds(100))
            #expect(outer.frame.height > originalHeight)
            state.selectPanel(nil)
            window.setContentSize(NSSize(width: 340, height: 420))
            state.windowHeight = 420
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func headerStaysPinnedWhileContentAndNativeWindowHaveDifferentHeights() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                           shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let host = NSHostingView(rootView: MenuBarRootView(store: store)
            .background(Color.black).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 680),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        // Deliberately retain an oversized native window, as happens for one frame
        // when a detail panel closes, a response arrives, or the composer shrinks.
        for height in [680.0, 550, 680] {
            window.setContentSize(NSSize(width: 340, height: height))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / 340
            let topInk = (0..<Int(100 * scale)).first { y in
                (Int(100 * scale)..<Int(240 * scale)).filter { x in
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return c.redComponent > 0.7 && c.greenComponent > 0.7 && c.blueComponent > 0.7
                }.count > Int(8 * scale)
            }
            #expect(try #require(topInk) < Int(35 * scale), "The title must not center itself in the old window height.")
            store.prompt = "hello"
            store.submitPrompt()
            await store.waitUntilIdle()
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func renderMenuStates() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".artifacts/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device:
            SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: true, repeatState: "off", progressMS: 74000)
        api.queueValue = (1...8).map {
            SpotifyQueueItem(uri: "spotify:track:test\($0)", name: "Evening Song \($0)", artists: [SpotifyArtist(name: "The Test Band")],
                             album: nil, images: nil, show: nil)
        }
        api.deviceValues = [SpotifyDevice(id: "mac", name: "This Mac", isActive: true, isRestricted: false),
                            SpotifyDevice(id: "phone", name: "iPhone", isActive: false, isRestricted: false)]
        await store.refreshPlayback()
        try await render(MenuBarRootView(store: store), name: "ready-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store), name: "ready-light", directory: output, scheme: .light)
        let presentation = PlayerPresentation()
        presentation.isDetached = true
        try await render(MenuBarRootView(store: store, panel: .queue, presentation: presentation),
                         name: "detached-queue-dark", directory: output, scheme: .dark)
        presentation.selectPanel(nil)
        try await render(MenuBarRootView(store: store, presentation: presentation),
                         name: "detached-ready-light", directory: output, scheme: .light)
        presentation.toggleMiniplayer()
        for detached in [false, true] {
            presentation.isDetached = detached
            for scheme in [ColorScheme.dark, .light] {
                try await render(MenuBarRootView(store: store, presentation: presentation),
                                 name: "miniplayer-\(detached ? "window" : "dropdown")-\(scheme)",
                                 directory: output, scheme: scheme)
            }
        }
        presentation.toggleMiniplayer()
        try await render(MenuBarRootView(store: store, panel: .queue), name: "queue-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store, panel: .outputs), name: "devices-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store, panel: .lyrics), name: "lyrics-consent-dark", directory: output, scheme: .dark)
        let lyrics = PlayerDetailsStore(spotify: api, lyrics: FixedLyrics())
        store.settings.lyricsEnabled = true
        await lyrics.loadLyrics(for: PlayerTests.track, enabled: true)
        try await render(ScrollView {
            PlayerDetailsView(store: store, details: lyrics, settings: store.settings, panel: .lyrics).padding(20)
        }.scrollIndicators(.never), name: "lyrics-text-dark", directory: output, scheme: .dark, height: 300)
        let timed = try #require(TimedLyrics(lrc: "[00:00.00]An open road\n[00:30.00]A quiet sky\n[01:00.00]The evening takes its time\n[01:20.00]A little light\n[01:30.00]A passing train\n[02:00.00]And we are home again"))
        try await render(SyncedLyricsView(store: store, lyrics: timed, trackURI: PlayerTests.track.uri).padding(20),
                         name: "lyrics-synced-dark", directory: output, scheme: .dark, height: 290)
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        try await render(MenuBarRootView(store: store), name: "recommendation-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store), name: "recommendation-light", directory: output, scheme: .light)
        store.logout()
        try await render(MenuBarRootView(store: store), name: "onboarding-dark", directory: output, scheme: .dark)
        store.prompt = "play some EDM songs"
        store.submitPrompt()
        try await render(MenuBarRootView(store: store, developerView: true), name: "developer-disconnected-dark",
                         directory: output, scheme: .dark)
        try await render(MenuBarIconView().padding(8), name: "menubar-icon-dark", directory: output, scheme: .dark,
                         width: 48, height: 40, minimumColors: 2)
        try await render(MenuBarIconView().padding(8), name: "menubar-icon-light", directory: output, scheme: .light,
                         width: 48, height: 40, minimumColors: 2)
        for state in [SpotifyCallbackPage.State.received, .denied, .expired] {
            try SpotifyCallbackPage.html(state: state).write(to: output.appendingPathComponent("spotify-\(state.rawValue).html"),
                                                             atomically: true, encoding: .utf8)
        }
        try await render(SettingsView(store: store, settings: store.settings), name: "settings-light",
                         directory: output, scheme: .light, width: 500, height: 620)
        let subscription = ChatGPTSession(settings: store.settings, rpc: FakeCodexRPC())
        await subscription.refresh()
        let connected = VibeCastStore(settings: store.settings, secrets: MemorySecrets(), spotify: FakeSpotify(),
                                       planner: FakePlanner(), notifications: FakeNotifications(), startAutomatically: false,
                                       chatGPT: subscription)
        try await render(SettingsView(store: connected, settings: store.settings), name: "settings-connected-dark",
                         directory: output, scheme: .dark, width: 500, height: 620)
    }

    private func render<V: View>(_ view: V, name: String, directory: URL, scheme: ColorScheme,
                                 width: CGFloat? = nil, height: CGFloat? = nil, minimumColors: Int = 30) async throws {
        let width = width ?? (view is MenuBarRootView ? PlayerPresentation.width : 400)
        let content = view.frame(width: width, height: height, alignment: .top)
            .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.98))
            .environment(\.colorScheme, scheme)
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height ?? 680),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height ?? 680)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let fittedHeight = height ?? host.fittingSize.height
        #expect(fittedHeight > 0 && fittedHeight <= 680)
        window.setContentSize(NSSize(width: width, height: fittedHeight))
        host.frame = NSRect(x: 0, y: 0, width: width, height: fittedHeight)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        if name.contains("lyrics") || name.contains("queue") {
            for scroll in scrollViews(in: host) {
                #expect(!scroll.hasVerticalScroller || scroll.verticalScroller?.isHidden == true,
                        "\(name) must not expose an outer or inner scrollbar.")
            }
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        var colors = Set<String>()
        for x in stride(from: bitmap.pixelsWide / 5, to: bitmap.pixelsWide * 4 / 5, by: 7) {
            for y in stride(from: bitmap.pixelsHigh / 5, to: bitmap.pixelsHigh * 4 / 5, by: 7) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    colors.insert("\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))")
                }
            }
        }
        #expect(colors.count > minimumColors, "\(name): the content area must render, not only the header.")
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.contentView = nil
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}

private struct PreviewTimedLyrics: LyricsServing {
    func lyrics(for track: SpotifyTrack) async throws -> Lyrics {
        .synced(TimedLyrics(lrc: "[00:00.00]An open road\n[00:30.00]A quiet sky\n[01:00.00]The evening takes its time\n[01:20.00]A little light\n[01:30.00]A passing train\n[02:00.00]And we are home again")!)
    }
}
