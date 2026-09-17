import Foundation
import UserNotifications

@MainActor
protocol Notifying {
    func recommend(_ recommendation: PendingPlaylistRecommendation) async throws
    func remove(_ id: UUID)
    func clear()
}

@MainActor
struct NotificationService: Notifying {
    static let category = "vibecast.playlistRecommendation"
    static let playAction = "vibecast.playlistRecommendation.play"
    static let magicAction = "vibecast.playlistRecommendation.castMagic"
    static let recommendationKey = "recommendationID"

    static func registerCategories() {
        let actions = [
            UNNotificationAction(identifier: playAction, title: "Sure!", options: []),
            UNNotificationAction(identifier: magicAction, title: "Cast Magic", options: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [], options: [])
        ])
    }

    func recommend(_ recommendation: PendingPlaylistRecommendation) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw UserFacingError("Notifications are off. Your playlist is ready here.")
            }
        } else if settings.authorizationStatus == .denied {
            throw UserFacingError("Notifications are off. Your playlist is ready here.")
        }
        let content = UNMutableNotificationContent()
        content.title = "Found a playlist for you"
        content.body = recommendation.playlist.displayName
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.userInfo = [Self.recommendationKey: recommendation.id.uuidString]
        try await center.add(UNNotificationRequest(identifier: recommendation.id.uuidString, content: content, trigger: nil))
    }

    func remove(_ id: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }
    func clear() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
