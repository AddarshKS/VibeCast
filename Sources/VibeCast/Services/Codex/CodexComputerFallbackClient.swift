import Foundation

struct CodexComputerFallbackClient {
    func handle(_ prompt: String) async -> VibeCastResult {
        VibeCastResult.placeholder(
            "Fallback stub",
            detail: "This broad music request is reserved for the future Codex Computer Plugin route: \(prompt)",
            source: .codexComputerFallback
        )
    }
}
