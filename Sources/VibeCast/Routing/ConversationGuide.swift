import Foundation

/// A small local clarification policy. It never claims to be a general chatbot, and
/// contextual playlist suggestions still pass through the usual Find/Sure flow.
enum ConversationGuide {
    enum Context: Equatable {
        case preference(mood: String?)
        case artist(mood: String?)
        case song
        case songOrArtist(title: String)
        case songArtist(title: String, queue: Bool = false)
    }

    struct Reply: Equatable {
        let title: String
        let detail: String
        let context: Context?
    }

    static func followUpRoute(for prompt: String, context: Context?) -> RequestRoute? {
        guard let context else { return nil }
        let value = RequestLanguage.command(prompt)
        guard !isExplicitCommand(value), !isDismissal(value) else { return nil }
        if isQuestionOrUnsupported(value), preference(in: value) == nil { return nil }
        switch context {
        case .preference(let mood):
            if let artist = RequestLanguage.artistPreference(value) {
                return .findPlaylist(prompt: "play songs by \(artist)")
            }
            if let preference = preference(in: value) {
                let combined = [mood, preference].compactMap { $0 }.joined(separator: " ")
                return .findPlaylist(prompt: "find \(combined) music")
            }
        case .artist:
            if let preference = preference(in: value) {
                return .findPlaylist(prompt: "find \(preference) music")
            }
            if isPlausibleName(value) {
                let artist = RequestLanguage.artistPreference(value) ?? value
                return .findPlaylist(prompt: "play songs by \(artist)")
            }
        case .song:
            if isPlausibleName(value) {
                return RequestRouter().route(VibeCastRequest(prompt: "play the song \(value)"))
            }
        case .songOrArtist(let title):
            if ["artist", "the artist", "an artist", "songs by them", "their music"].contains(value) {
                return .findPlaylist(prompt: "play songs by \(title)")
            }
        case .songArtist(let title, let queue):
            if isPlausibleName(value) {
                let artist = RequestLanguage.artistPreference(value) ?? value
                let query = TrackQuery(title: title, artist: artist)
                return .directSpotify(queue ? .queueTrack(query: query) : .playTrack(query: query))
            }
        }
        return nil
    }

    static func reply(to prompt: String, context: Context? = nil) -> Reply {
        let value = RequestLanguage.command(prompt)
        if value == "shuffle" {
            return Reply(title: "Shuffle on or off?", detail: "Say “shuffle on” or “shuffle off”.", context: nil)
        }
        if value == "repeat" {
            return Reply(title: "How should playback repeat?", detail: "Say “repeat on”, “repeat off”, or “repeat this song”.", context: nil)
        }
        if ["queue", "add to queue", "add to my queue"].contains(value) {
            return Reply(title: "Which song should I queue?", detail: "Include a title and artist, for example “Queue Animals by Martin Garrix”.", context: nil)
        }
        if isDismissal(value) {
            return Reply(title: "Whenever you're ready.", detail: "Ask for a song, an artist, or a mood.", context: nil)
        }
        if let context, case .songOrArtist(let title) = context, ["song", "the song", "a song", "track"].contains(value) {
            return Reply(title: "Who performs \(title)?", detail: "Reply with the artist so I can find the right recording.",
                         context: .songArtist(title: title))
        }
        if let context, case .songArtist(let title, let queue) = context,
           ["artist", "an artist", "the artist", "song", "a song", "the song", "track"].contains(value) {
            return Reply(title: "Who performs \(title)?",
                         detail: queue ? "Reply with the artist's name to add this song to the queue." : "Reply with the artist's name to find the right recording.",
                         context: context)
        }
        if ["artist", "an artist", "my favorite artist", "favourite artist", "favorite artist"].contains(value) {
            return Reply(title: "Which artist?", detail: "Reply with a name. I'll suggest a playlist for you to confirm.",
                         context: .artist(mood: mood(in: prompt)))
        }
        if ["song", "a song", "a specific song", "specific song", "track"].contains(value) {
            return Reply(title: "Which song?", detail: "Include the artist, for example “Play Animals by Martin Garrix”.",
                         context: .song)
        }
        if isQuestionOrUnsupported(value), !value.matches(#"^(what should i (?:play|listen to)|what do you (?:think|recommend))"#) {
            return Reply(title: "I can help with your music.",
                         detail: "Ask for a song and artist, find a mood or genre playlist, make a playlist, or control playback. I can't answer general questions or change unsupported Spotify settings.",
                         context: nil)
        }
        if let mood = mood(in: value) {
            return Reply(title: "Let's find something \(mood).",
                         detail: "Which genre would suit you, or would you prefer an artist? I'll suggest a playlist before playing it.",
                         context: .preference(mood: mood))
        }
        if let context {
            switch context {
            case .songOrArtist(let title): return unresolvedTrackReply(title: title)
            case .songArtist(let title, _):
                return Reply(title: "Who performs \(title)?", detail: "Reply with the artist, or start a new request.", context: context)
            case .artist:
                return Reply(title: "Which artist?", detail: "Reply with their name, or ask for a mood or genre instead.", context: context)
            case .song:
                return Reply(title: "Which song?", detail: "Tell me the title and artist, or start a new request.", context: context)
            case .preference:
                return Reply(title: "Give me a musical direction.",
                             detail: "Try a genre like jazz, a mood like energetic, or say “an artist”.", context: context)
            }
        }
        return Reply(title: "What would you like to hear?",
                     detail: "Tell me a mood or genre, say “an artist”, or name a song. Playlist suggestions wait for your confirmation.",
                     context: .preference(mood: nil))
    }

    static func unresolvedTrackReply(title: String, queue: Bool = false) -> Reply {
        if queue {
            return Reply(title: "Who performs \(title)?",
                         detail: "I couldn't confidently match that song. Reply with the artist to add it to the queue. Nothing has been queued or played.",
                         context: .songArtist(title: title, queue: true))
        }
        return Reply(title: "Song or artist?",
              detail: "I couldn't confidently match “\(title)”. Reply “artist” for their playlists, or “song” to add the performer. Nothing has played.",
              context: .songOrArtist(title: title))
    }

    /// Only compact preference phrases qualify without a command; incidental mentions
    /// such as "tell me about jazz history" must remain conversation.
    static func preference(in prompt: String) -> String? {
        var value = RequestLanguage.musicCommand(prompt).musicNormalized
        value = value.replacingOccurrences(of: #"^(?:play|find|put on|listen to|start)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:i want|i like|i prefer|i feel like|how about|what about|give me|me|some|something|anything|a|an|for|songs?|music|tracks|playlists?|mix|vibe|vibing)\b"#,
                                  with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let vocabulary: Set<String> = ["edm", "jazz", "lofi", "lo", "fi", "chill", "workout", "focus", "coding", "party",
                                       "rock", "soft", "pop", "classical", "ambient", "electronic", "dance", "house", "techno",
                                       "hip", "hop", "rap", "r", "b", "soul", "funk", "disco", "country", "folk", "indie", "metal",
                                       "punk", "reggae", "blues", "latin", "k", "afrobeats", "acoustic", "instrumental", "piano",
                                       "calm", "gentle", "quiet", "relaxing", "energetic", "upbeat", "happy", "sad", "comforting",
                                       "road", "trip", "late", "night", "driving", "sleep", "study", "studying", "running", "morning",
                                       "evening", "dinner", "romantic", "nostalgic", "bollywood", "hindi", "tamil", "korean"]
        let words = value.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 7, words.allSatisfy({ vocabulary.contains($0) }) else { return nil }
        return value
    }

    private static func mood(in prompt: String) -> String? {
        let value = prompt.musicNormalized
        if value.matches(#"\b(tired|stressed|overwhelmed|anxious|relax|relaxing|calm)\b"#) { return "calm" }
        if value.matches(#"\b(sad|down|lonely|heartbroken)\b"#) { return "comforting" }
        if value.matches(#"\b(happy|excited|celebrating|energized|energetic)\b"#) { return "upbeat" }
        return nil
    }

    private static func isExplicitCommand(_ value: String) -> Bool {
        DirectCommandClassifier().action(for: value) != nil
            || value.matches(#"^(play|find|put on|listen to|start|queue|add to|make|create|build|curate|cast magic|pause|stop|resume|skip|next|previous|shuffle|repeat|turn|switch|change|transfer)\b"#)
    }

    private static func isDismissal(_ value: String) -> Bool {
        ["no", "no thanks", "never mind", "nevermind", "cancel", "forget it", "that's all", "nothing"].contains(value)
    }

    private static func isQuestionOrUnsupported(_ value: String) -> Bool {
        value.matches(#"^(what|why|how|who|where|when|tell|explain|do |does |is |are |don'?t|do not|never|no |not )"#)
            || value.matches(#"\b(volume|mute|unmute|delete|remove|rename|weather|email|calendar|news)\b"#)
    }

    private static func isPlausibleName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 140 && !isQuestionOrUnsupported(value)
            && !["yes", "sure", "okay", "ok", "maybe", "idk", "i don't know", "song", "a song", "the song", "track", "artist", "an artist", "the artist", "anything", "something"].contains(value)
    }
}
