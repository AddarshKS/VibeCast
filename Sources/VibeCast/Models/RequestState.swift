import Foundation

enum RequestState: Equatable {
    case idle
    case routing
    case executing(RequestRoute)
    case completed(VibeCastResult)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            "Ready"
        case .routing:
            "Understanding request..."
        case .executing(let route):
            "Using \(route.displayName)..."
        case .completed(let result):
            result.title
        case .failed(let message):
            message
        }
    }
}
