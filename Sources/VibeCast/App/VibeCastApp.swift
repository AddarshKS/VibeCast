import SwiftUI

@main
struct VibeCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = VibeCastStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(store: store)
                .frame(width: 380)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
