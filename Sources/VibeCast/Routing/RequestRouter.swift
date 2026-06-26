import Foundation

struct RequestRouter {
    private let directClassifier = DirectCommandClassifier()

    func route(_ request: VibeCastRequest) -> RequestRoute {
        let prompt = request.prompt
        let normalized = prompt.lowercased()

        if let action = directClassifier.action(for: prompt) {
            return .directSpotify(action)
        }

        if looksLikeCasualChat(normalized) {
            return .codexChat(prompt: prompt)
        }

        if looksBroadOrMoodBased(normalized) {
            return .codexComputerFallback(prompt: prompt)
        }

        if normalized.hasPrefix("play ") || normalized.hasPrefix("queue ") {
            return .codexInterpreter(prompt: prompt)
        }

        return .codexChat(prompt: prompt)
    }

    private func looksLikeCasualChat(_ prompt: String) -> Bool {
        let chatMarkers = [
            "i am tired",
            "i'm tired",
            "im tired",
            "damn",
            "how are you",
            "what do you think",
            "i feel",
            "i'm feeling",
            "im feeling"
        ]

        return chatMarkers.contains { prompt.contains($0) }
    }

    private func looksBroadOrMoodBased(_ prompt: String) -> Bool {
        let fallbackMarkers = [
            "some ",
            "playlist",
            "vibe",
            "vibing",
            "mood",
            "road trip",
            "late-night",
            "late night",
            "coding",
            "edm",
            "party",
            "workout",
            "focus",
            "white girl music"
        ]

        return fallbackMarkers.contains { prompt.contains($0) }
    }
}
