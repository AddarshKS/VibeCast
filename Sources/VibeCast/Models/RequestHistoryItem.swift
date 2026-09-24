import Foundation

struct RequestHistoryItem: Identifiable, Equatable {
    enum Status: Equatable {
        case success
        case failure
        case cancelled

        var symbol: String {
            switch self {
            case .success: "checkmark"
            case .failure: "exclamationmark.circle"
            case .cancelled: "stop.circle"
            }
        }
    }

    let id = UUID()
    let prompt: String
    let routeName: String
    let message: String
    let status: Status
    let stage: String?
    let createdAt: Date

    init(prompt: String, routeName: String, message: String, status: Status, stage: String? = nil, createdAt: Date = .now) {
        self.prompt = prompt
        self.routeName = routeName
        self.message = message
        self.status = status
        self.stage = stage
        self.createdAt = createdAt
    }
}
