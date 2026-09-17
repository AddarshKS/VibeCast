import AppKit
import ImageIO
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
@Suite(.serialized)
struct VisualTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func renderAdvancedSettingsWithNativeFormRows() async throws {
        _ = NSApplication.shared
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".artifacts/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for expanded in [false, true] {
            for scheme in [ColorScheme.dark, .light] {
                let view = Form {
                    Section("Lyrics") {
                        Toggle("Use LRCLIB", isOn: .constant(true))
                        Text("Song title, artist, album and duration are shared with LRCLIB only while the lyrics panel is open. No Spotify credentials are shared.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    AdvancedSettingsSection(draft: .constant(SettingsDraft(settings: store.settings)),
                                            isExpanded: .constant(expanded))
                }
                .formStyle(.grouped).scrollContentBackground(.hidden).tint(.teal)
                try await render(view, name: "settings-advanced-\(expanded ? "expanded" : "collapsed")-\(scheme)",
                                 directory: output, scheme: scheme, width: 500, height: 480)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func renderImmersivePlayerAndBothMiniDetails() async throws {
        _ = NSApplication.shared
        URLProtocol.registerClass(ImmersiveArtworkFixture.self)
        defer { URLProtocol.unregisterClass(ImmersiveArtworkFixture.self) }
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".artifacts/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let (store, api, _, _, _) = try await StoreTests().fixture(lyrics: PreviewTimedLyrics())
        let track = SpotifyTrack(uri: "spotify:track:immersive", name: "Evening Light",
                                 artists: [.init(name: "The Test Band")],
                                 album: .init(images: [.init(url: URL(string: "https://artwork.vibecast.test/cover.png")!)]),
                                 isPlayable: true, durationMS: 213000)
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: track,
            device: .init(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: true, repeatState: "off", progressMS: 74000)
        await store.refreshPlayback()
        store.settings.lyricsEnabled = true
        api.queueValue = (0..<8).map {
            SpotifyQueueItem(uri: "spotify:track:q\($0)", name: "Evening Song \($0 + 1)",
                             artists: [.init(name: "The Test Band")], album: nil, images: nil, show: nil, durationMS: 213000)
        }
        await store.playerDetails.loadLyrics(for: track, enabled: true)
        let state = PlayerPresentation()
        state.windowHeight = 340
        state.toggleMiniplayer()
        for detached in [false, true] {
            state.isDetached = detached
            for panel in [nil, PlayerPanel.lyrics, .queue] {
                if let current = state.miniplayerPanel { state.toggleMiniplayerPanel(current) }
                if let panel { state.toggleMiniplayerPanel(panel) }
                let view = MiniplayerView(store: store, presentation: state,
                    toggleMiniplayer: {}, toggleWindow: {}, toggleDetail: { state.toggleMiniplayerPanel($0) }, selectPanel: { _ in })
                    .environment(\.playerDensity, .compact)
                let host = NSHostingView(rootView: view.frame(width: 340))
                #expect(abs(host.fittingSize.height - 340) < 1)
                try await render(view, name: "immersive-\(detached ? "window" : "dropdown")-\(panel?.rawValue ?? "player")",
                                 directory: output, scheme: .dark, width: 340, height: 340)
            }
        }
        try await render(ImmersiveMiniplayerView(store: store, presentation: state,
                         toggleMiniplayer: {}, toggleWindow: {}, selectPanel: { _ in })
            .environment(\.playerDensity, .compact), name: "immersive-light-appearance", directory: output,
                         scheme: .light, width: 340, height: 340)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"), arguments: 0...5, [false, true])
    func queueHeaderStaysAlignedThroughoutOpeningAndRefresh(historyCount: Int, mini: Bool) async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        for index in 0...historyCount {
            api.playbackValue = SpotifyPlayback(isPlaying: true,
                item: SpotifyTrack(uri: "spotify:track:h\(index)", name: "History \(index)",
                                   artists: [], album: nil, isPlayable: true),
                device: nil, shuffleState: false, repeatState: "off")
            await store.refreshPlayback()
        }
        for detached in [false, true] {
            let state = PlayerPresentation()
            state.isDetached = detached
            let height: CGFloat = mini ? 340 : 544
            state.windowHeight = height
            if mini { state.toggleMiniplayer() }
            let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
            host.sizingOptions = []
            host.safeAreaRegions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: height),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            try await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeOut(duration: 0.2)) { setQueueOpen(true, state: state, mini: mini) }
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
            // Refresh and reopening must discard a previously exposed history section.
            let marker = try #require(queueMarker(in: host))
            let scroll = try #require(marker.enclosingScrollView)
            scroll.contentView.scroll(to: .zero)
            marker.needsReset = true
            marker.reconcileLayout()
            await store.playerDetails.refreshQueue()
            try await Task.sleep(for: .milliseconds(100))
            let document = try #require(scroll.documentView)
            #expect(abs(marker.convert(marker.bounds, to: document).minY - scroll.contentView.bounds.minY) < 1)
            let upcomingHeaderTop = marker.convert(marker.bounds, to: host).minY
            if historyCount > 0 {
                let anchor = marker.convert(marker.bounds, to: document).minY
                #expect(marker.applySectionDrag(delta: -40))
                #expect(abs(scroll.contentView.bounds.minY - (anchor - 12)) < 1)
                #expect(!marker.physics.historyRevealed)
                #expect(marker.applySectionDrag(delta: -60))
                try await waitForQueueOffset(scroll, target: 0)
                #expect(marker.physics.historyRevealed)
                #expect(abs(scroll.contentView.bounds.minY) < 1)
                #expect(abs(document.convert(document.bounds, to: host).minY - upcomingHeaderTop) < 1,
                        "Recently Played must have the same top clearance as Next Up after snapping.")
                let historyBottom = marker.historyBottom
                if mini { #expect(historyBottom == 0, "Mini history must return with one pull, not first scroll through the separator.") }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: historyBottom))
                #expect(marker.applySectionDrag(delta: 40))
                #expect(abs(scroll.contentView.bounds.minY - historyBottom - 12) < 1)
                #expect(marker.applySectionDrag(delta: 60))
                try await waitForQueueOffset(scroll, target: anchor)
                #expect(!marker.physics.historyRevealed)
                #expect(abs(scroll.contentView.bounds.minY - anchor) < 1)
                #expect(abs(marker.convert(marker.bounds, to: host).minY - upcomingHeaderTop) < 1,
                        "Returning to Next Up must restore exactly the original header clearance.")
            }
            scroll.contentView.scroll(to: .zero)
            setQueueOpen(false, state: state, mini: mini)
            try await Task.sleep(for: .milliseconds(100))
            setQueueOpen(true, state: state, mini: mini)
            try await Task.sleep(for: .milliseconds(250))
            let reopened = try #require(queueMarker(in: host))
            let reopenedScroll = try #require(reopened.enclosingScrollView)
            let reopenedDocument = try #require(reopenedScroll.documentView)
            #expect(abs(reopened.convert(reopened.bounds, to: reopenedDocument).minY - reopenedScroll.contentView.bounds.minY) < 1)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"), arguments: [false, true])
    func minimumQueueHeightKeepsAllHistoryReachableAndResizesInPlace(detached: Bool) async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let state = PlayerPresentation()
        state.isDetached = detached
        state.windowHeight = 344
        state.selectPanel(.queue)
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 344),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for index in 0...5 {
            api.playbackValue = SpotifyPlayback(isPlaying: true,
                item: SpotifyTrack(uri: "spotify:track:h\(index)", name: "History \(index)",
                                   artists: [], album: nil, isPlayable: true, durationMS: 213000),
                device: nil, shuffleState: false, repeatState: "off")
            await store.refreshPlayback()
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let marker = try #require(queueMarker(in: host))
            let scroll = try #require(marker.enclosingScrollView)
            let document = try #require(scroll.documentView)
            let anchor = marker.convert(marker.bounds, to: document).minY
            #expect(abs(scroll.contentView.bounds.minY - anchor) < 1)
            guard index > 0 else { continue }
            #expect(marker.applySectionDrag(delta: -100))
            try await waitForQueueOffset(scroll, target: 0)
            let bottom = marker.historyBottom
            if bottom > 10 {
                #expect(!marker.applySectionDrag(delta: 5), "Overflowing history must allow native browsing.")
            }
            // Cross the history's last row and start pulling in one continuous gesture.
            #expect(marker.applySectionDrag(delta: bottom + 40))
            #expect(abs(scroll.contentView.bounds.minY - bottom - 12) < 1)
            #expect(marker.applySectionDrag(delta: 60))
            try await waitForQueueOffset(scroll, target: anchor)
            #expect(!marker.physics.historyRevealed)
        }
        let marker = try #require(queueMarker(in: host))
        let scroll = try #require(marker.enclosingScrollView)
        #expect(marker.applySectionDrag(delta: -100))
        try await waitForQueueOffset(scroll, target: 0)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: marker.historyBottom))
        state.windowHeight = 544
        window.setContentSize(NSSize(width: 340, height: 544))
        try await Task.sleep(for: .milliseconds(150))
        #expect(marker.physics.historyRevealed)
        #expect(abs(scroll.contentView.bounds.minY) < 1,
                "Once all history fits, resizing must keep the section at its top.")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"), arguments: [false, true])
    func queueRefreshesImmediatelyOnConfirmedAndExternalTrackChanges(mini: Bool) async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                           shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let state = PlayerPresentation()
        let height: CGFloat = mini ? 340 : 544
        state.windowHeight = height
        if mini { state.toggleMiniplayer() }
        setQueueOpen(true, state: state, mini: mini)
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        for index in 0..<3 {
            let item = SpotifyQueueItem(uri: "spotify:track:fresh\(index)", name: "Fresh \(index)",
                                        artists: [], album: nil, images: nil, show: nil)
            api.queueValue = [item]
            if index == 0 {
                store.control(.next)
                await store.waitUntilIdle()
            } else {
                api.playbackValue = SpotifyPlayback(isPlaying: true,
                    item: SpotifyTrack(uri: "spotify:track:external\(index)", name: "External \(index)",
                                       artists: [], album: nil, isPlayable: true),
                    device: nil, shuffleState: false, repeatState: "off")
                await store.refreshPlayback()
            }
            for _ in 0..<40 {
                if case .loaded(let items) = store.playerDetails.queue, items.first?.uri == item.uri { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard case .loaded(let items) = store.playerDetails.queue else {
                Issue.record("Track changes must update the open queue without waiting for its periodic timer.")
                return
            }
            #expect(items.first?.uri == item.uri)
        }
        let reads = api.queueReads
        store.control(.shuffle(true))
        await store.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(100))
        #expect(api.queueReads == reads, "An unchanged track must not restart the queue refresh loop.")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"), arguments: [PlayerPanel.lyrics, .queue])
    func normalReadingModesKeepOriginalHeaderSpacingWithoutDragGrip(panel: PlayerPanel) async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                           shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let state = PlayerPresentation()
        state.selectPanel(panel)
        state.windowHeight = 544
        var origins: [String: CGPoint] = [:]
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state)
            .onPreferenceChange(RippleOrigins.self) { origins = $0 })
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 544),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for detached in [false, true, false] {
            state.isDetached = detached
            for height in [344.0, 700] {
                state.windowHeight = height
                window.setContentSize(NSSize(width: 340, height: height))
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                // AppKit hitTest takes parent coordinates; the hosting view is flipped.
                let target = host.convert(NSPoint(x: 170, y: 6), to: host.superview)
                let hit = try #require(host.hitTest(target))
                #expect(String(describing: type(of: hit)) != "DragView",
                        "Normal reading modes must not expose an eight-dot grip above the header.")
                #expect(abs(try #require(origins["album"]).y - 20 - 12) < 0.5,
                        "Original top spacing must match in dropdown and pop-out at every height.")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"), arguments: [PlayerPanel.lyrics, .queue])
    func readingControlsSurviveGrowingAfterRipple(panel: PlayerPanel) async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture(lyrics: PreviewTimedLyrics())
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track, device: nil,
                                           shuffleState: false, repeatState: "off", progressMS: 20000)
        await store.refreshPlayback()
        store.settings.lyricsEnabled = true
        let state = PlayerPresentation()
        state.isDetached = true
        state.maximumHeight = 1100
        state.windowHeight = 544
        var origins: [String: CGPoint] = [:]
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state)
            .onPreferenceChange(RippleOrigins.self) { origins = $0 }
            .environment(\.colorScheme, .dark).background(Color(white: 0.12)))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 544),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeInOut(duration: 0.45)) { state.selectPanel(panel) }
        try await Task.sleep(for: .milliseconds(500))
        for height in [344.0, 544, 760, 1000, 544, 344] {
            state.recordResize(height)
            window.setContentSize(NSSize(width: 340, height: height))
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let albumCenterY = try #require(origins["album"]).y
            #expect(albumCenterY < 50, "The metadata header must stay at the top.")
            if let readingScroll = scrollViews(in: host).first {
                let frame = readingScroll.convert(readingScroll.bounds, to: host)
                #expect(frame.minY >= 60, "The reading viewport must not cover its metadata header: \(frame).")
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / 340
            var headerInk = 0
            for x in Int(65 * scale)..<Int(240 * scale) {
                for y in Int((albumCenterY - 20) * scale)..<Int((albumCenterY + 1) * scale) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       min(color.redComponent, color.greenComponent, color.blueComponent) > 0.7 { headerInk += 1 }
                }
            }
            #expect(headerInk > 50, "Song metadata must remain visible above the scrolling content.")
            // Each transport icon must still have visible pixels after the completed
            // ripple is resized far beyond its original height, then shrunk again.
            for centerX in [40.0, 81.67, 123.33, 170, 216.67, 258.33, 300] {
                var ink = 0
                for x in Int((centerX - 10) * scale)..<Int((centerX + 10) * scale) {
                    for y in Int((height - 72) * scale)..<Int((height - 52) * scale) {
                        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           max(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 { ink += 1 }
                    }
                }
                #expect(ink > 6, "Transport button at \(centerX) must remain visible at window height \(height).")
            }
        }
    }

    private func queueMarker(in view: NSView) -> QueueScrollBehavior.Marker? {
        if let marker = view as? QueueScrollBehavior.Marker { return marker }
        return view.subviews.lazy.compactMap { queueMarker(in: $0) }.first
    }

    private func setQueueOpen(_ open: Bool, state: PlayerPresentation, mini: Bool) {
        if mini {
            if (state.miniplayerPanel == .queue) != open { state.toggleMiniplayerPanel(.queue) }
        } else { state.selectPanel(open ? .queue : nil) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"),
          arguments: [false, true], [(false, 0), (false, 12), (true, 0), (true, 12)])
    func growingHistoryPreservesUpcomingPositionAndNeverFocusesComposerOnOpen(detached: Bool, content: (Bool, Int)) async throws {
        _ = NSApplication.shared
        let (mini, upcomingCount) = content
        let (store, api, _, _, _) = try await StoreTests().fixture()
        let state = PlayerPresentation()
        state.isDetached = detached
        api.queueValue = (0..<upcomingCount).map {
            SpotifyQueueItem(uri: "spotify:track:q\($0)", name: "Upcoming \($0)", artists: [], album: nil, images: nil, show: nil)
        }
        let height: CGFloat = mini ? 340 : 544
        state.windowHeight = height
        if mini { state.toggleMiniplayer() }
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: state))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!(window.firstResponder is NSTextView), "Opening the player must not start editing the request.")
        setQueueOpen(true, state: state, mini: mini)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let marker = try #require(queueMarker(in: host))
        let scroll = try #require(marker.enclosingScrollView)
        let document = try #require(scroll.documentView)
        var previousOffset: CGFloat = 0
        for index in 0...6 {
            api.playbackValue = SpotifyPlayback(isPlaying: true,
                item: SpotifyTrack(uri: "spotify:track:n\(index)", name: "Song \(index)", artists: [], album: nil, isPlayable: true),
                device: nil, shuffleState: false, repeatState: "off")
            await store.refreshPlayback()
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(16))
                host.layoutSubtreeIfNeeded()
                let anchor = marker.convert(marker.bounds, to: document).minY
                #expect(abs(scroll.contentView.bounds.minY - anchor) < 1,
                        "History count \(min(index, 5)): clip \(scroll.contentView.bounds.minY), header \(anchor). Up Next must stay aligned.")
                #expect(!marker.physics.historyRevealed)
            }
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
    func activeLyricEmphasisPreservesWrappingAndRestoresContrast() async throws {
        _ = NSApplication.shared
        for width: CGFloat in [180, 312] {
            for overArtwork in [false, true] {
                var heights: [CGFloat] = []
                var brightness: [CGFloat] = []
                for active in [false, true] {
                    let label = LyricLineLabel(text: "A longer lyric line that wraps without moving its neighbors",
                                              active: active, overArtwork: overArtwork)
                        .environment(\.playerDensity, .compact)
                        .environment(\.colorScheme, .dark)
                        .frame(width: width).padding(6).background(.black)
                    let host = NSHostingView(rootView: label)
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width + 12, height: 180),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.contentView = host
                    defer { window.contentView = nil }
                    try await Task.sleep(for: .milliseconds(50))
                    let height = host.fittingSize.height
                    heights.append(height)
                    window.setContentSize(NSSize(width: width + 12, height: height))
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    var light: CGFloat = 0
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                                light += color.redComponent + color.greenComponent + color.blueComponent
                            }
                        }
                    }
                    brightness.append(light)
                }
                #expect(heights[0] == heights[1], "Emphasis must not rewrap lines or shift lyric scroll anchors.")
                #expect(brightness[1] > brightness[0] * 1.5, "The current lyric must stand out clearly on either background.")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func restoredLandingFitsAllSuggestionsAndGrowsForRequests() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: .init(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let state = PlayerPresentation()
        state.windowHeight = 420
        var natural: CGFloat = 0
        var sections: [String: CGFloat] = [:]
        let host = NSHostingView(rootView: MenuBarRootView(store: store, resize: { natural = $0 }, presentation: state)
            .onPreferenceChange(PanelMeasurements.self) { sections = $0 })
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(200))
        let landingHeight = natural
        #expect(landingHeight == 418, "Restore the titled landing screen and its original spacing.")
        window.setContentSize(NSSize(width: 340, height: natural))
        state.windowHeight = natural
        try await Task.sleep(for: .milliseconds(150))
        let scroll = try #require(scrollViews(in: host).first)
        let body = try #require(sections["body-landing"])
        #expect(body <= scroll.contentView.bounds.height + 1, "All three inspirations must fit without scrolling.")
        store.prompt = String(repeating: "Music for an evening drive. ", count: 12)
        try await Task.sleep(for: .milliseconds(200))
        #expect(natural > landingHeight, "Multiline requests must still grow the landing surface.")
        store.prompt = "find me a soft rock playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        try await Task.sleep(for: .milliseconds(200))
        #expect(natural > landingHeight, "Recommendations must retain automatic content sizing.")
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
            var previousViewport: CGFloat?
            var previousHeight: CGFloat?
            for height in [500.0, 550, 680] {
                state.windowHeight = height
                window.setContentSize(NSSize(width: PlayerPresentation.width, height: height))
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                let scrolls = scrollViews(in: host)
                #expect(scrolls.count == 1, "Lyrics must have one scroll surface, not nested scrolling panels.")
                let lyricsScroll = try #require(scrolls.first)
                let frame = lyricsScroll.convert(lyricsScroll.bounds, to: host)
                #expect(host.bounds.contains(frame))
                if let previousViewport, let previousHeight {
                    #expect(abs(lyricsScroll.frame.height - previousViewport - height + previousHeight) < 1,
                            "Only the reading viewport should grow; header and controls stay fixed.")
                }
                previousViewport = lyricsScroll.frame.height
                previousHeight = height
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func renderLandingAndReadingModes() async throws {
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
        state.windowHeight = 390
        try await render(MenuBarRootView(store: store, presentation: state), name: "compact-player-dark",
                         directory: output, scheme: .dark, height: 390)
        state.selectPanel(.lyrics)
        state.maximumHeight = 1100
        for height in [344.0, 390, 650, 760, 1000] {
            state.recordResize(height)
            try await render(MenuBarRootView(store: store, presentation: state), name: "reading-lyrics-\(Int(height))-dark",
                             directory: output, scheme: .dark, height: height)
        }
        state.recordResize(650)
        try await render(MenuBarRootView(store: store, presentation: state), name: "reading-lyrics-light",
                         directory: output, scheme: .light, height: 650)
        api.queueValue = (1...8).map {
            SpotifyQueueItem(uri: "spotify:track:q\($0)", name: "Evening Song \($0)",
                             artists: [.init(name: "The Test Band")], album: nil, images: nil, show: nil, durationMS: 213000)
        }
        state.selectPanel(.queue)
        for height in [344.0, 544, 1000] {
            state.recordResize(height)
            try await render(MenuBarRootView(store: store, presentation: state), name: "reading-queue-\(Int(height))-dark",
                             directory: output, scheme: .dark, height: height)
        }
        state.isDetached = false
        state.resetWindowSize()
        state.selectPanel(.lyrics)
        state.windowHeight = 550
        for scheme in [ColorScheme.dark, .light] {
            try await render(MenuBarRootView(store: store, presentation: state),
                             name: "popover-lyrics-\(scheme)", directory: output, scheme: scheme, height: 550)
        }
        api.playbackValue = SpotifyPlayback(isPlaying: false, item: PlayerTests.track, device:
            SpotifyDevice(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: false, repeatState: "off", progressMS: 0)
        await store.refreshPlayback()
        try await render(MenuBarRootView(store: store, presentation: state), name: "lyrics-song-start-dark",
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
        for panel in [PlayerPanel.queue, .lyrics] {
            state.selectPanel(panel)
            try await Task.sleep(for: .milliseconds(100))
            #expect(requestedHeight > 420)
            let readingScroll = try #require(scrollViews(in: host).first)
            let originalHeight = readingScroll.frame.height
            #expect(host.bounds.contains(readingScroll.convert(readingScroll.bounds, to: host)),
                    "Reading content must remain inside the surface before native resizing.")
            window.setContentSize(NSSize(width: 340, height: requestedHeight))
            state.windowHeight = requestedHeight
            try await Task.sleep(for: .milliseconds(100))
            #expect(readingScroll.frame.height > originalHeight)
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
            #expect(try #require(topInk) < Int(65 * scale), "The player must not center itself in the old window height.")
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
                         name: "detached-queue-dark", directory: output, scheme: .dark,
                         height: PlayerPresentation.readingHeight)
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
        try await render(MenuBarRootView(store: store, panel: .queue), name: "queue-dark", directory: output,
                         scheme: .dark, height: PlayerPresentation.readingHeight)
        try await render(MenuBarRootView(store: store, panel: .outputs), name: "devices-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store, panel: .lyrics), name: "lyrics-consent-dark", directory: output,
                         scheme: .dark, height: PlayerPresentation.readingHeight)
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
        #expect(fittedHeight > 0 && fittedHeight <= max(680, height ?? 0))
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
            // Tall lyric windows may contain only a few lines near the top.
            for y in stride(from: min(bitmap.pixelsHigh / 5, bitmap.pixelsWide / 3), to: bitmap.pixelsHigh * 4 / 5, by: 7) {
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

private final class ImmersiveArtworkFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "artwork.vibecast.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [CGColor(red: 0.98, green: 0.83, blue: 0.65, alpha: 1),
                         CGColor(red: 0.76, green: 0.3, blue: 0.4, alpha: 1),
                         CGColor(red: 0.18, green: 0.4, blue: 0.42, alpha: 1)] as CFArray, locations: [0, 0.5, 1]) else { return }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 128, y: 128), options: [])
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fillEllipse(in: CGRect(x: 38, y: 68, width: 52, height: 52))
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                           headerFields: ["Content-Type": "image/png"])!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data as Data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
