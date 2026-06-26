import Foundation
import UserNotifications

struct NotificationService {
    func send(result: VibeCastResult) {
        let content = UNMutableNotificationContent()
        content.title = result.title
        if let detail = result.detail {
            content.body = detail
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
