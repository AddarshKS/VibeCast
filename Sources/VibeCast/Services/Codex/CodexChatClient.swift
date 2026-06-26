import Foundation

struct CodexChatClient {
    func respond(to prompt: String) async -> VibeCastResult {
        let response: String
        if prompt.lowercased().contains("tired") {
            response = "Sounds like you need a reset. I can play something calm, or you can just vent for a bit."
        } else {
            response = "I’m here. Give me a song, a mood, or just tell me what kind of moment you’re in."
        }

        return VibeCastResult.placeholder(response, source: .codexChat)
    }
}
