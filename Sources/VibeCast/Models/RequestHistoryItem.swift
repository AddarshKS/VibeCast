import Foundation

struct RequestHistoryItem: Identifiable, Equatable {
    enum Status: Equatable {
        case success
        case failure
    }

    let id = UUID()
    let prompt: String
    let routeName: String
    let message: String
    let status: Status
    let createdAt: Date

    init(prompt: String, routeName: String, message: String, status: Status, createdAt: Date = .now) {
        self.prompt = prompt
        self.routeName = routeName
        self.message = message
        self.status = status
        self.createdAt = createdAt
    }
}
