import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = VibeCastStore()
    private var presentation: MenuBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        presentation = MenuBarController(store: store)
        NotificationService.registerCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) { store.chatGPT.shutdown() }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let rawID = response.notification.request.content.userInfo["recommendationID"] as? String,
              let id = UUID(uuidString: rawID) else { return }
        await NotificationActionRouter.shared.handle(actionIdentifier: response.actionIdentifier, recommendationID: id)
    }
}
