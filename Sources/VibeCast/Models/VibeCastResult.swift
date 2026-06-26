import Foundation

struct VibeCastResult: Equatable {
    enum Source: Equatable {
        case spotifyAPI
        case codexInterpreter
        case codexChat
        case codexComputerFallback
        case local
    }

    let title: String
    let detail: String?
    let source: Source
    let resolvedItem: String?

    init(title: String, detail: String? = nil, source: Source, resolvedItem: String? = nil) {
        self.title = title
        self.detail = detail
        self.source = source
        self.resolvedItem = resolvedItem
    }

    static func placeholder(_ title: String, detail: String? = nil, source: Source) -> VibeCastResult {
        VibeCastResult(title: title, detail: detail, source: source)
    }
}
