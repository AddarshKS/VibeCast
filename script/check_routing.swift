import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("FAIL: \(message)")
        exit(1)
    }
}

let classifier = DirectCommandClassifier()

expect(classifier.action(for: "Pause") == .pause, "Pause routes to pause")
expect(classifier.action(for: "unpause") == .resume, "unpause routes to resume")
expect(classifier.action(for: "Skip this song") == .next, "skip phrase routes to next")
expect(classifier.action(for: "go back") == .previous, "go back routes to previous")
expect(classifier.action(for: "turn shuffle on") == .shuffle(true), "shuffle on parses")
expect(classifier.action(for: "disable shuffle") == .shuffle(false), "shuffle off parses")
expect(classifier.action(for: "repeat off") == .repeatMode(.off), "repeat off parses")
expect(classifier.action(for: "repeat on") == .repeatMode(.context), "repeat on parses")
expect(classifier.action(for: "loop this song") == .repeatMode(.track), "repeat current song parses")
expect(
    classifier.action(for: "Play Animals by Martin Garrix") ==
    .playTrack(query: TrackQuery(title: "Animals", artist: "Martin Garrix")),
    "play track by artist parses"
)
expect(
    classifier.action(for: "Queue Peace of Blood by Citadelle") ==
    .queueTrack(query: TrackQuery(title: "Peace Of Blood", artist: "Citadelle")),
    "queue track by artist parses"
)
expect(classifier.action(for: "Play Peace of Blood") == nil, "play without artist is not direct")
expect(
    classifier.action(for: "Change speaker to iPhone") ==
    .transferPlayback(deviceName: "Iphone"),
    "device command parses"
)

let router = RequestRouter()
expect(
    router.route(VibeCastRequest(prompt: "Play Animals by Martin Garrix")) ==
    .directSpotify(.playTrack(query: TrackQuery(title: "Animals", artist: "Martin Garrix"))),
    "direct track routes to Spotify"
)
expect(
    router.route(VibeCastRequest(prompt: "Play Peace of Blood")) ==
    .codexInterpreter(prompt: "Play Peace of Blood"),
    "incomplete track routes to interpreter"
)
expect(
    router.route(VibeCastRequest(prompt: "I am vibe coding, play me some EDM")) ==
    .codexComputerFallback(prompt: "I am vibe coding, play me some EDM"),
    "broad mood prompt routes to fallback"
)
expect(
    router.route(VibeCastRequest(prompt: "Damn I am so tired")) ==
    .codexChat(prompt: "Damn I am so tired"),
    "casual prompt routes to chat"
)

let interpreter = CodexInterpreterClient(useCodex: false)
let candidates = [
    SpotifyResolvedTrack(
        uri: "spotify:track:peace-flood",
        title: "Peace of Flood",
        artist: "Citadelle"
    ),
    SpotifyResolvedTrack(
        uri: "spotify:track:wrong",
        title: "The Peace Broker's Ledger",
        artist: "Ambient Awakening Life 69"
    )
]

let playResolution = try await interpreter.resolve(prompt: "Play Peace of Flood", candidates: candidates)
expect(
    playResolution.action == .playResolvedTrack(candidates[0]),
    "interpreter resolves Play Peace of Flood to supplied Spotify candidate"
)

let queueResolution = try await interpreter.resolve(prompt: "Queue Peace of Flood", candidates: candidates)
expect(
    queueResolution.action == .queueResolvedTrack(candidates[0]),
    "interpreter resolves Queue Peace of Flood to supplied Spotify candidate"
)

let lowerPlayResolution = try await interpreter.resolve(prompt: "Play peace of flood", candidates: candidates)
expect(
    lowerPlayResolution.action == .playResolvedTrack(candidates[0]),
    "interpreter resolves lowercase Play peace of flood"
)

do {
    _ = try await interpreter.resolve(
        prompt: "Play completely unrelated thing",
        candidates: candidates
    )
    expect(false, "low-confidence unrelated prompt should fail safely")
} catch {
    expect(true, "low-confidence unrelated prompt fails safely")
}

print("Routing checks passed")
