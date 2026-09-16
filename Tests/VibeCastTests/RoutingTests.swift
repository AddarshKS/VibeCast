import Foundation
import Testing
@testable import VibeCast

final class RoutingTests {
    @Test func testDirectControlsAndSpecificSongs() {
        let classifier = DirectCommandClassifier()
        #expect((classifier.action(for: "Pause")) == (.pause))
        #expect((classifier.action(for: "Skip this song")) == (.next))
        #expect((classifier.action(for: "turn shuffle on")) == (.shuffle(true)))
        #expect((classifier.action(for: "loop this song")) == (.repeatMode(.track)))
        #expect((classifier.action(for: "Play Animals by Martin Garrix")) == (.playTrack(query: TrackQuery(title: "Animals", artist: "Martin Garrix"))))
        for value in ["songs", "some songs", "music", "me some tracks"] {
            #expect(classifier.action(for: "play \(value) by Ed Sheeran") == nil)
        }
    }

    @Test func testFindMakeAndConversationRouting() {
        let router = RequestRouter()
        for prompt in ["play some EDM songs", "late night driving", "road trip songs",
                       "find me a soft rock playlist", "play songs by Ed Sheeran", "play some music by Citadelle",
                       "I'm tired, play some jazz"] {
            #expect((router.route(VibeCastRequest(prompt: prompt))) == (.findPlaylist(prompt: prompt)))
        }
        for prompt in ["make me a soft rock playlist", "create a playlist", "curate songs for a drive",
                       "I'm tired, make me a playlist"] {
            #expect((router.route(VibeCastRequest(prompt: prompt))) == (.makePlaylist(prompt: prompt)))
        }
        for prompt in ["damn I'm tired", "what should I play?", "how are you?"] {
            #expect((router.route(VibeCastRequest(prompt: prompt))) == (.conversation(prompt: prompt)))
        }
        #expect((router.route(VibeCastRequest(prompt: "Play Peace of Blood"))) == (.track(prompt: "Play Peace of Blood")))
        #expect((router.route(VibeCastRequest(prompt: "queue Peace of Blood"))) == (.track(prompt: "queue Peace of Blood")))
        #expect((router.route(VibeCastRequest(prompt: "play \"Focus\""))) == (.track(prompt: "play \"Focus\"")))
    }

    @Test func testSearchKeepsUnicodeAndMatchesOnlySuppliedCandidates() {
        #expect((MusicSearch.playlistQuery("play songs by Ed Sheeran")) == ("this is ed sheeran"))
        #expect((MusicSearch.playlistQuery("find me a soft rock playlist")) == ("soft rock"))
        #expect(MusicSearch.playlistQuery("I'm tired, play some jazz") == "jazz")
        #expect(MusicSearch.playlistQuery("I am vibe coding, play some EDM") == "edm")
        #expect(("Beyonce".musicNormalized) == ("Beyoncé".musicNormalized))
        #expect(!(MusicSearch.playlistQuery("play songs by 宇多田ヒカル").isEmpty))
        let track = SpotifyResolvedTrack(uri: "spotify:track:0000000000000000000001", title: "Peace of Blood", artist: "Citadelle")
        #expect((MusicSearch.matchTrack(title: "Peace of Blood", artist: "Citadelle", candidates: [track])) == (track))
        #expect(MusicSearch.matchTrack(title: "Peace of Blood", artist: "Wrong artist", candidates: [track]) == nil)
        #expect(MusicSearch.matchTrack(title: "Completely unrelated", artist: nil, candidates: [track]) == nil)
        let remix = SpotifyResolvedTrack(uri: track.uri, title: "Peace of Blood - Remix", artist: "Citadelle")
        #expect(MusicSearch.matchTrack(title: "Peace of Blood", artist: "Citadelle", candidates: [remix]) == nil)
        let unrelated = SpotifyResolvedPlaylist(uri: "spotify:playlist:unrelated", name: "This Is Another Artist", ownerName: nil, description: nil)
        let artist = SpotifyResolvedPlaylist(uri: "spotify:playlist:artist", name: "This Is Ed Sheeran", ownerName: nil, description: nil)
        #expect(MusicSearch.matchPlaylist(query: "this is ed sheeran", candidates: [unrelated]) == nil)
        #expect(MusicSearch.matchPlaylist(query: "this is ed sheeran", candidates: [unrelated, artist]) == artist)
    }

    @Test func testRecommendationExpiryOwnershipAndConsumption() {
        let playlist = SpotifyResolvedPlaylist(uri: "spotify:playlist:example", name: "Drive", ownerName: nil, description: nil)
        var item = PendingPlaylistRecommendation(accountID: "alice", originalPrompt: "drive", playlist: playlist, searchPhrase: "drive")
        #expect(item.isActionable(accountID: "alice"))
        #expect(!(item.isActionable(accountID: "bob")))
        #expect(!(item.isActionable(accountID: "alice", now: item.createdAt.addingTimeInterval(3601))))
        item.status = .accepted
        #expect(!(item.isActionable(accountID: "alice")))
    }
}
