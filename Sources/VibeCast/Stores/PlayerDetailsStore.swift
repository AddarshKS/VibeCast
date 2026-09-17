import Foundation

enum PlayerPanel: String { case lyrics, queue, outputs }
enum PlayerLoadState<Value> {
    case idle, loading, loaded(Value), failed(String)
}

@MainActor
final class PlayerDetailsStore: ObservableObject {
    @Published private(set) var queue: PlayerLoadState<[SpotifyQueueItem]> = .idle
    @Published private(set) var lyrics: PlayerLoadState<Lyrics> = .idle
    @Published private(set) var devices: PlayerLoadState<[SpotifyDevice]> = .idle
    @Published private(set) var recentlyPlayed: [SpotifyTrack] = []
    private var observedTrack: SpotifyTrack?
    private let spotify: any SpotifyServing
    private let provider: any LyricsServing
    private var queueGeneration = UUID()
    private var lyricsGeneration = UUID()
    private(set) var lyricsTrackURI: String?
    private var devicesGeneration = UUID()

    init(spotify: any SpotifyServing, lyrics: any LyricsServing = LyricsClient()) {
        self.spotify = spotify
        self.provider = lyrics
    }

    // Session-local history follows confirmed playback, not button presses or queue predictions.
    func observePlayback(_ playback: SpotifyPlayback?) {
        guard let track = playback?.item else { return }
        if let previous = observedTrack, previous.uri != track.uri {
            recentlyPlayed = Array((recentlyPlayed + [previous]).suffix(5))
        }
        observedTrack = track
    }

    func refreshQueue() async {
        let generation = UUID()
        queueGeneration = generation
        if case .loaded = queue {} else { queue = .loading }
        do {
            let items = try await spotify.queue()
            try Task.checkCancellation()
            guard generation == queueGeneration else { return }
            queue = .loaded(items)
        } catch {
            guard generation == queueGeneration, !Task.isCancelled else { return }
            queue = .failed(error.localizedDescription)
        }
    }

    func loadLyrics(for track: SpotifyTrack?, enabled: Bool, force: Bool = false) async {
        if enabled, let track, !force, lyricsTrackURI == track.uri,
           case .loaded = lyrics { return }
        let generation = UUID()
        lyricsGeneration = generation
        lyrics = .idle
        lyricsTrackURI = nil
        guard enabled, let track else { return }
        lyrics = .loading
        do {
            let value = try await provider.lyrics(for: track)
            try Task.checkCancellation()
            guard generation == lyricsGeneration else { return }
            lyricsTrackURI = track.uri
            lyrics = .loaded(value)
        } catch {
            guard generation == lyricsGeneration, !Task.isCancelled else { return }
            lyrics = .failed("Lyrics couldn't be loaded. Check your connection and try again.")
        }
    }

    func refreshDevices() async {
        let generation = UUID()
        devicesGeneration = generation
        if case .loaded = devices {} else { devices = .loading }
        do {
            let values = try await spotify.devices()
            try Task.checkCancellation()
            guard generation == devicesGeneration else { return }
            devices = .loaded(values)
        } catch {
            guard generation == devicesGeneration, !Task.isCancelled else { return }
            devices = .failed(error.localizedDescription)
        }
    }

    func reset() {
        observedTrack = nil
        recentlyPlayed = []
        queueGeneration = UUID()
        lyricsGeneration = UUID()
        lyricsTrackURI = nil
        devicesGeneration = UUID()
        queue = .idle
        lyrics = .idle
        devices = .idle
    }
}
