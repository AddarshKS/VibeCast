import Foundation
import Testing
@testable import VibeCast

struct RequestInterpretationTests {
    private let router = RequestRouter()
    private let song = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "Peace of Blood", artist: "Citadelle")

    @Test(arguments: ["pause please", "Pause!", "Could you please pause the music?", "Hey VibeCast, pause, thanks.", "pasue"])
    func politeControlsRemainDirect(prompt: String) {
        #expect(router.route(VibeCastRequest(prompt: prompt)) == .directSpotify(.pause))
    }

    @Test(arguments: ["please listen to Peace of Blood by Citadelle!", "Can you play Peace of Blood by Citadelle, please?", "put on “Peace of Blood” by Citadelle", "paly Peace of Blood by Citadelle"])
    func exactSongFormsKeepTitleAndArtist(prompt: String) {
        #expect(router.route(VibeCastRequest(prompt: prompt)) == .directSpotify(.playTrack(query: TrackQuery(title: "Peace Of Blood", artist: "Citadelle"))))
    }

    @Test(arguments: ["play songs by Martin Garrix", "play some more by Martin Garrix", "listen to the artist Martin Garrix", "find me some tracks by Martin Garrix"])
    func artistRequestsNeverBecomeTracksNamedSongs(prompt: String) {
        #expect(router.route(VibeCastRequest(prompt: prompt)) == .findPlaylist(prompt: prompt))
        #expect(MusicSearch.playlistQuery(prompt) == "this is martin garrix")
    }

    @Test(arguments: ["Don't pause", "Could you not pause?", "what should I play?", "why do songs make us cry?", "explain jazz history", "play something", "play it"])
    func ambiguousQuestionsDoNotStartPlaybackOrSearch(prompt: String) {
        #expect(router.route(VibeCastRequest(prompt: prompt)) == .conversation(prompt: prompt))
    }

    @Test func explicitTitlesSurviveGenreWordsAndQuotedBy() {
        #expect(router.route(VibeCastRequest(prompt: "play the song Focus")) == .track(prompt: "play the song Focus"))
        #expect(router.route(VibeCastRequest(prompt: "play \"Stand by Me\"")) == .track(prompt: "play \"Stand by Me\""))
        #expect(DirectCommandClassifier().action(for: "play \"Stand by Me\" by Ben E. King") ==
                .playTrack(query: TrackQuery(title: "Stand By Me", artist: "Ben E. King")))
        #expect(MusicSearch.trackQuery("Can you play the song “Focus”, please?") == "focus")
        #expect(MusicSearch.trackQuery("play \"Please\"") == "please")
    }

    @Test func aSongNamedPleaseDoesNotBecomeResume() {
        #expect(router.route(VibeCastRequest(prompt: "play Please")) == .track(prompt: "play Please"))
        #expect(MusicSearch.trackQuery("play Please") == "please")
    }

    @Test func politeQueueRequestsKeepQueueIntent() {
        let prompt = "Could you add to my queue Peace of Blood, please?"
        #expect(router.route(VibeCastRequest(prompt: prompt)) == .track(prompt: prompt))
        #expect(MusicSearch.isQueueRequest(prompt))
        #expect(MusicSearch.trackQuery(prompt) == "peace of blood")
        #expect(!MusicSearch.isQueueRequest("play Queue by Example"))
        #expect(DirectCommandClassifier().action(for: "please queue Peace of Blood by Citadelle") ==
                .queueTrack(query: TrackQuery(title: "Peace Of Blood", artist: "Citadelle")))
    }

    @Test func conservativeTyposNeedAnArtistAndUniqueMatch() {
        #expect(MusicSearch.matchTrack(title: "Peace of Blodo", artist: "Citadelle", candidates: [song]) == song)
        #expect(MusicSearch.matchTrack(title: "Peace of Blood", artist: "Citadell", candidates: [song]) == song)
        #expect(MusicSearch.matchTrack(title: "Peace of Blodo", artist: nil, candidates: [song]) == nil)
        #expect(MusicSearch.matchTrack(title: "Peace of Blodo", artist: "Someone Else", candidates: [song]) == nil)
        #expect(MusicSearch.matchTrack(title: "Peace of Blodo", artist: "Citadell", candidates: [song]) == nil)
        let alternative = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000002", title: "Peace of Bloot", artist: song.artist)
        #expect(MusicSearch.matchTrack(title: "Peace of Bloof", artist: song.artist, candidates: [song, alternative]) == nil)
    }

    @Test func sharedTitlesRequireArtistInsteadOfArbitraryFirstResult() {
        let anotherArtist = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000002", title: song.title, artist: "Another Artist")
        #expect(MusicSearch.matchTrack(title: song.title, artist: nil, candidates: [song, anotherArtist]) == nil)
        #expect(MusicSearch.matchTrack(title: song.title, artist: song.artist, candidates: [anotherArtist, song]) == song)
        let duplicateRecording = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000003", title: song.title, artist: song.artist)
        #expect(MusicSearch.matchTrack(title: song.title, artist: nil, candidates: [song, duplicateRecording]) == song)
        let remix = SpotifyResolvedTrack(uri: song.uri, title: song.title + " - Remix", artist: song.artist)
        #expect(MusicSearch.matchTrack(title: song.title, artist: song.artist, candidates: [remix]) == nil)
        let unrelatedLongerTitle = SpotifyResolvedTrack(uri: song.uri, title: song.title + " Never Ends", artist: song.artist)
        #expect(MusicSearch.matchTrack(title: song.title, artist: song.artist, candidates: [unrelatedLongerTitle]) == nil)
        let feature = SpotifyResolvedTrack(uri: song.uri, title: song.title + " (feat. Another Artist)", artist: song.artist)
        #expect(MusicSearch.matchTrack(title: song.title, artist: song.artist, candidates: [feature]) == feature)
    }

    @Test func moodConversationCarriesContextIntoConfirmedFind() {
        let reply = ConversationGuide.reply(to: "damn I'm tired")
        #expect(reply.context == .preference(mood: "calm"))
        #expect(ConversationGuide.followUpRoute(for: "jazz", context: reply.context) == .findPlaylist(prompt: "find calm jazz music"))
        #expect(ConversationGuide.followUpRoute(for: "how about jazz", context: reply.context) == .findPlaylist(prompt: "find calm jazz music"))
        #expect(MusicSearch.playlistQuery("how about jazz") == "jazz")
        #expect(ConversationGuide.followUpRoute(for: "pause please", context: reply.context) == nil)
        #expect(ConversationGuide.followUpRoute(for: "yes", context: reply.context) == nil)
        #expect(ConversationGuide.followUpRoute(for: "no thanks", context: reply.context) == nil)
        #expect(ConversationGuide.reply(to: "never mind", context: reply.context).context == nil)
    }

    @Test func artistAndSongClarificationRemainSeparate() {
        let unresolved = ConversationGuide.unresolvedTrackReply(title: "Martin Garrix")
        #expect(ConversationGuide.followUpRoute(for: "artist", context: unresolved.context) == .findPlaylist(prompt: "play songs by Martin Garrix"))
        let artistQuestion = ConversationGuide.reply(to: "an artist")
        #expect(ConversationGuide.followUpRoute(for: "Ed Sheeran", context: artistQuestion.context) == .findPlaylist(prompt: "play songs by ed sheeran"))
        #expect(ConversationGuide.followUpRoute(for: "what is the weather", context: artistQuestion.context) == nil)
        let title = ConversationGuide.unresolvedTrackReply(title: "Hello")
        let performer = ConversationGuide.reply(to: "song", context: title.context)
        #expect(performer.context == .songArtist(title: "Hello"))
        #expect(ConversationGuide.followUpRoute(for: "Adele", context: performer.context) == .directSpotify(.playTrack(query: TrackQuery(title: "Hello", artist: "adele"))))
    }

    @Test func choosingASongPreservesLiteralGenreNamedTitles() {
        let reply = ConversationGuide.reply(to: "a specific song")
        #expect(ConversationGuide.followUpRoute(for: "Focus", context: reply.context) ==
                .track(prompt: "play the song focus"))
        #expect(ConversationGuide.followUpRoute(for: "Focus by H.E.R.", context: reply.context) ==
                .directSpotify(.playTrack(query: TrackQuery(title: "Focus", artist: "H.e.r"))))
        #expect(ConversationGuide.followUpRoute(for: "Songs by Example", context: reply.context) ==
                .directSpotify(.playTrack(query: TrackQuery(title: "Songs", artist: "Example"))))
    }

    @Test func artistClarificationLetsUserChooseAGenreInstead() {
        let reply = ConversationGuide.reply(to: "an artist")
        #expect(ConversationGuide.followUpRoute(for: "jazz", context: reply.context) == .findPlaylist(prompt: "find jazz music"))
        #expect(ConversationGuide.followUpRoute(for: "how about soft rock", context: reply.context) == .findPlaylist(prompt: "find soft rock music"))
    }

    @Test func unresolvedQueueKeepsQueueIntentThroughPerformerClarification() {
        let reply = ConversationGuide.unresolvedTrackReply(title: "Hello", queue: true)
        #expect(reply.context == .songArtist(title: "Hello", queue: true))
        #expect(ConversationGuide.followUpRoute(for: "Adele", context: reply.context) ==
                .directSpotify(.queueTrack(query: TrackQuery(title: "Hello", artist: "adele"))))
        #expect(ConversationGuide.followUpRoute(for: "artist", context: reply.context) == nil)
        #expect(ConversationGuide.reply(to: "artist", context: reply.context).context == reply.context)
        #expect(ConversationGuide.reply(to: "yes", context: reply.context).context == reply.context)
        // A fresh, explicit playback request intentionally overrides the old queue context.
        #expect(ConversationGuide.followUpRoute(for: "play Hello by Adele", context: reply.context) == nil)
    }

    @Test(arguments: ["what is the weather", "turn the volume down", "delete this playlist", "how are you?"])
    func unsupportedConversationStatesCapabilitiesWithoutInventingAnswers(prompt: String) {
        let reply = ConversationGuide.reply(to: prompt)
        #expect(reply.context == nil)
        #expect(reply.detail.contains("can't answer general questions"))
    }
}
