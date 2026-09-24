import AppKit
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
@Suite(.serialized)
struct RequestFeedbackVisualTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"), arguments: [false, true])
    func recoveryFeedbackPreservesPlayerAndComposerAndRestoresLanding(unknownCreation: Bool) async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.playbackValue = SpotifyPlayback(isPlaying: true, item: PlayerTests.track,
            device: .init(id: "test", name: "This Mac", isActive: true, isRestricted: false),
            shuffleState: false, repeatState: "off")
        await store.refreshPlayback()
        let presentation = PlayerPresentation()
        presentation.windowHeight = 430
        var naturalHeight: CGFloat = 0
        var sections: [String: CGFloat] = [:]
        let host = NSHostingView(rootView: MenuBarRootView(store: store, resize: { naturalHeight = $0 }, presentation: presentation)
            .onPreferenceChange(PanelMeasurements.self) { sections = $0 }
            .background(Color(white: 0.12)).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = makeWindow(host, height: 430)
        defer { window.contentView = nil }
        try await settle(host)
        let landingHeight = naturalHeight
        let playerHeight = try #require(sections["top"])
        #expect(landingHeight == 430, "The approved player and 22-point landing gap must remain unchanged.")

        if unknownCreation { api.creationError = URLError(.networkConnectionLost) }
        else { api.failWrite = true }
        store.prompt = "make an evening jazz playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        #expect(store.latestError != nil)
        #expect((store.pendingPlaylistCreation != nil) == unknownCreation)
        #expect((store.unfinishedPlaylist != nil) == !unknownCreation)
        try await settle(host)
        #expect(naturalHeight > landingHeight && naturalHeight <= 680,
                "Recovery must grow the scrollable response area within the screen height limit.")
        #expect(sections["top"] == playerHeight, "Request feedback must not move or resize player controls.")
        window.setContentSize(NSSize(width: 340, height: naturalHeight))
        presentation.windowHeight = naturalHeight
        try await settle(host)
        try assertScrollableContentFits(host, sections: sections)
        try save(host, name: unknownCreation ? "request-creation-recovery-dark" : "request-playlist-draft-dark")

        let draft = "An unfinished request\nWith acoustic guitars\nAnd quiet vocals"
        store.prompt = draft
        store.clear()
        try await settle(host)
        #expect(store.prompt == draft)
        #expect(store.latestError == nil)
        #expect(store.playlistRecoveryID != nil, "Dismissing feedback must retain recovery controls.")
        window.setContentSize(NSSize(width: 340, height: 430))
        presentation.windowHeight = 430
        try await settle(host)
        try assertScrollableContentFits(host, sections: sections)
        try save(host, name: unknownCreation ? "request-recovery-after-dismiss-dark" : "request-draft-after-dismiss-dark")

        let recoveryID = try #require(store.playlistRecoveryID)
        store.abandonPlaylistRecovery(id: recoveryID)
        #expect(store.prompt == draft)
        store.prompt = ""
        try await settle(host)
        #expect(naturalHeight == landingHeight)
        #expect(sections["top"] == playerHeight)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func longRecoveryErrorAndDiagnosticsRemainScrollableWithoutCoveringComposer() async throws {
        _ = NSApplication.shared
        let (store, api, _, _, _) = try await StoreTests().fixture()
        api.creationError = URLError(.timedOut)
        store.prompt = "make an evening jazz playlist"
        store.submitPrompt()
        await store.waitUntilIdle()
        api.recoveryError = UserFacingError(String(repeating: "Spotify couldn't finish checking this playlist. Keep the recovery and try again shortly. ", count: 8))
        store.recoverPlaylistCreation()
        await store.waitUntilIdle()
        store.prompt = "A new request I haven't sent yet"
        let presentation = PlayerPresentation()
        presentation.windowHeight = 430
        var sections: [String: CGFloat] = [:]
        let host = NSHostingView(rootView: MenuBarRootView(store: store, presentation: presentation)
            .onPreferenceChange(PanelMeasurements.self) { sections = $0 }
            .background(Color(white: 0.98)).environment(\.colorScheme, .light))
        host.sizingOptions = []
        host.safeAreaRegions = []
        let window = makeWindow(host, height: 430, appearance: .aqua)
        defer { window.contentView = nil }
        try await settle(host)
        try assertScrollableContentFits(host, sections: sections)
        try save(host, name: "request-long-error-light")
        let scroll = try #require(scrollViews(in: host).first)
        let document = try #require(scroll.documentView)
        #expect(document.bounds.height > scroll.contentView.bounds.height,
                "Long errors must scroll instead of compressing or covering the composer.")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 1,
                "The recovery controls at the bottom must remain reachable.")
        try save(host, name: "request-long-error-recovery-controls-light")

        presentation.advanced = true
        try await settle(host)
        try assertScrollableContentFits(host, sections: sections)
        #expect(store.lastRequestOutcome == "Failed")
        #expect(store.lastRequestStage == "Locate previous playlist creation")
        #expect(store.lastRequestPrompt == "Recover Test Mix")
        try save(host, name: "request-failure-diagnostics-light")
    }

    private func makeWindow<V: View>(_ host: NSHostingView<V>, height: CGFloat, appearance: NSAppearance.Name = .darkAqua) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: appearance)
        return window
    }

    private func settle(_ host: NSView) async throws {
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
    }

    private func assertScrollableContentFits(_ host: NSView, sections: [String: CGFloat]) throws {
        let top = try #require(sections["top"])
        let bottom = try #require(sections["bottom"])
        #expect(top + bottom + 20 <= host.bounds.height, "Player and composer need a usable request viewport between them.")
        let scroll = try #require(scrollViews(in: host).first)
        let viewport = scroll.convert(scroll.bounds, to: host)
        #expect(host.bounds.contains(viewport), "Response scrolling must stay within the player window.")
        #expect(viewport.height > 20)
        let document = try #require(scroll.documentView)
        #expect(document.bounds.width <= scroll.contentView.bounds.width + 1,
                "Error, stage, and recovery text must wrap without horizontal overflow.")
    }

    private func save(_ host: NSView, name: String) throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".artifacts/previews")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide >= 340 && bitmap.pixelsHigh >= 430)
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }
}
