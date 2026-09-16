import AppKit
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
struct VisualTests {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 680),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        // Deliberately retain an oversized native window, as happens for one frame
        // when a detail panel closes, a response arrives, or the composer shrinks.
        for height in [680.0, 550, 680] {
            window.setContentSize(NSSize(width: 400, height: height))
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / 400
            let topInk = (0..<Int(100 * scale)).first { y in
                (Int(20 * scale)..<Int(160 * scale)).filter { x in
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
        try await render(MenuBarRootView(store: store, presentation: presentation),
                         name: "detached-ready-light", directory: output, scheme: .light)
        try await render(MenuBarRootView(store: store, panel: .queue), name: "queue-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store, panel: .outputs), name: "devices-dark", directory: output, scheme: .dark)
        try await render(MenuBarRootView(store: store, panel: .lyrics), name: "lyrics-consent-dark", directory: output, scheme: .dark)
        let lyrics = PlayerDetailsStore(spotify: api, lyrics: FixedLyrics())
        store.settings.lyricsEnabled = true
        await lyrics.loadLyrics(for: PlayerTests.track, enabled: true)
        try await render(ScrollView {
            PlayerDetailsView(store: store, details: lyrics, settings: store.settings, panel: .lyrics, close: {}).padding(20)
        }, name: "lyrics-text-dark", directory: output, scheme: .dark, height: 300)
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
                                 width: CGFloat = 400, height: CGFloat? = nil, minimumColors: Int = 30) async throws {
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
        host.layoutSubtreeIfNeeded()
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
        #expect(colors.count > minimumColors, "The content area must render, not only the header.")
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.contentView = nil
    }
}
