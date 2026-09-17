import AppKit
import Testing
@testable import VibeCast

@MainActor
extension PresentationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func settingsSupportActivationAndAcceptFirstMouse() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        controller.showSettings()
        try await Task.sleep(for: .milliseconds(150))
        let window = try #require(controller.settingsWindow)
        // Like the other presentation tests, real activation requires the packaged app.
        #expect(window.isVisible && window.canBecomeKey)
        if NSApp.isActive { #expect(window.isKeyWindow) }
        #expect(window.contentView is FirstClickHostingView<SettingsView>)
        #expect(window.contentView?.acceptsFirstMouse(for: nil) == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func menuKeepsRequestedOrderAndOnlyShowsLocalAIStatus() async throws {
        _ = NSApplication.shared
        let (store, _, _, _, _) = try await StoreTests().fixture()
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        store.settings.aiProvider = .chatGPT
        let menu = controller.makeStatusMenu()
        #expect(menu.items.prefix(4).map(\.title) == ["Advance Mode View", "Settings", "Quit VibeCast", "Contact Us!"])
        #expect(menu.items[4].isSeparatorItem)
        #expect(menu.items[5].title == "Spotify Connected")
        #expect(menu.items[6].title == "OpenAI Checking Connection")
        #expect(menu.items.prefix(4).allSatisfy { $0.isEnabled && $0.image != nil && $0.action != nil })
        #expect(menu.items.suffix(2).allSatisfy { !$0.isEnabled && $0.image != nil && $0.action == nil })
        controller.playerPresentation.toggleAdvanced()
        #expect(controller.makeStatusMenu().items[0].state == .on)
        store.logout()
        #expect(controller.makeStatusMenu().items[5].title == "Spotify Disconnected")
        for provider in [AIProvider.hosted, .personalAPI] {
            store.settings.aiProvider = provider
            #expect(controller.makeStatusMenu().items.count == 6)
        }
        #expect(MenuBarController.contactURL.absoluteString == "mailto:addarshshrivastava@gmail.com")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_TEST_PRESENTATION"] == "1"))
    func localAccountStatusUsesTheUsersSignedInSession() async throws {
        _ = NSApplication.shared
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.aiProvider = .chatGPT
        let rpc = FakeCodexRPC()
        let session = ChatGPTSession(settings: settings, rpc: rpc)
        await session.refresh()
        let store = VibeCastStore(settings: settings, secrets: MemorySecrets(), spotify: FakeSpotify(),
                                 planner: FakePlanner(), notifications: FakeNotifications(), startAutomatically: false,
                                 chatGPT: session)
        let controller = MenuBarController(store: store)
        defer { controller.close() }
        let menu = controller.makeStatusMenu()
        #expect(menu.items.last?.title == "OpenAI Connected")
        rpc.signedIn = false
        await session.refresh()
        try await Task.sleep(for: .milliseconds(30))
        #expect(menu.items.last?.title == "OpenAI Disconnected")
        #expect(controller.makeStatusMenu().items.last?.title == "OpenAI Disconnected")
    }

    @Test func statusMenuOriginIsBelowIconOnEitherDisplay() {
        for rect in [NSRect(x: 900, y: 850, width: 24, height: 24), NSRect(x: -1200, y: -30, width: 24, height: 24)] {
            let origin = MenuBarController.statusMenuOrigin(below: rect)
            #expect(origin.x == rect.minX)
            #expect(origin.y == rect.minY - 6)
        }
    }
}
