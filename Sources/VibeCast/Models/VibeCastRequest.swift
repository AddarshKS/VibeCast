import Foundation

struct VibeCastRequest: Identifiable, Equatable {
    let id: UUID
    let prompt: String
    let createdAt: Date

    init(prompt: String, createdAt: Date = .now) {
        self.id = UUID()
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }
}
