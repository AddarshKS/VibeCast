import Foundation

struct VibeCastResult: Equatable {
    enum Source: Equatable { case spotifyAPI, track, findPlaylist, makePlaylist, conversation, local }
    let title: String
    var detail: String? = nil
    let source: Source
    var resolvedItem: String? = nil
    var playlist: SpotifyResolvedPlaylist? = nil
}
