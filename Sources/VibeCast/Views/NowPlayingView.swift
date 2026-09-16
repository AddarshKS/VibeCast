import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var store: VibeCastStore
    @Binding var panel: PlayerPanel?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                CoverArtwork(url: store.playback?.item?.resolvedTrack.artworkURL, size: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.playback?.isPlaying == true ? "NOW PLAYING" : (store.playback?.item == nil ? "YOUR SPOTIFY" : "PAUSED"))
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(store.playback?.item?.name ?? (store.playback?.isPlaying == true ? "Playing on Spotify" : "Nothing playing"))
                        .font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text(store.playback?.item?.resolvedTrack.artist ?? (store.playback?.isPlaying == true ? "Open Spotify for this item." : "Choose your next song."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let duration = store.playback?.item?.durationMS, duration > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = store.playback?.elapsedMS(observedAt: store.playbackUpdatedAt, now: context.date) ?? 0
                    VStack(spacing: 5) {
                        ProgressView(value: Double(elapsed), total: Double(duration))
                            .progressViewStyle(PlaybackProgressStyle()).accessibilityLabel("Song progress")
                        HStack {
                            Text(time(elapsed))
                            Spacer()
                            Text(time(duration))
                        }
                        .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 0) {
                PlayerIconButton(title: "Shuffle", symbol: "shuffle", active: store.playback?.shuffleState == true,
                                 pending: store.pendingPlayerAction == .shuffle(!(store.playback?.shuffleState ?? false))) {
                    store.control(.shuffle(!(store.playback?.shuffleState ?? false)))
                }.disabled(store.isBusy)
                Spacer(minLength: 4)
                PlayerIconButton(title: "Repeat", symbol: store.playback?.repeatState == "track" ? "repeat.1" : "repeat",
                                 active: (store.playback?.repeatState ?? "off") != "off",
                                 pending: store.pendingPlayerAction == .repeatMode(nextRepeat)) {
                    store.control(.repeatMode(nextRepeat))
                }.disabled(store.isBusy)
                Spacer(minLength: 4)
                PlayerIconButton(title: "Previous song", symbol: "backward.end.fill", pending: store.pendingPlayerAction == .previous) { store.control(.previous) }
                    .disabled(store.isBusy)
                Spacer(minLength: 4)
                Button { store.control(store.playback?.isPlaying == true ? .pause : .resume) } label: {
                    ZStack {
                        Image(systemName: store.playback?.isPlaying == true ? "pause.fill" : "play.fill")
                            .opacity(transportPending ? 0 : 1)
                        if transportPending { ProgressView().controlSize(.small) }
                    }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .frame(width: 42, height: 42)
                        .background(Color.primary, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(store.isBusy)
                .help(store.playback?.isPlaying == true ? "Pause" : "Play")
                .accessibilityLabel(store.playback?.isPlaying == true ? "Pause" : "Play")
                Spacer(minLength: 4)
                PlayerIconButton(title: "Next song", symbol: "forward.end.fill", pending: store.pendingPlayerAction == .next) { store.control(.next) }
                    .disabled(store.isBusy)
                Spacer(minLength: 4)
                PlayerIconButton(title: "Lyrics", symbol: "quote.bubble", active: panel == .lyrics) { toggle(.lyrics) }
                Spacer(minLength: 4)
                PlayerIconButton(title: "Up next", symbol: "list.bullet", active: panel == .queue) { toggle(.queue) }
            }
            Button { toggle(.outputs) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "hifispeaker")
                    Text(store.playback?.device?.name ?? "Choose a Spotify device").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(panel == .outputs ? Color.teal : Color.secondary)
                .frame(height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Change Spotify device").accessibilityLabel("Change Spotify device")
        }
        .padding(16)
        .modifier(RaisedPlayerSurface())
    }

    private func toggle(_ value: PlayerPanel) { panel = panel == value ? nil : value }
    private var transportPending: Bool { store.pendingPlayerAction == .pause || store.pendingPlayerAction == .resume }
    private func time(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    private var nextRepeat: SpotifyRepeatMode {
        switch store.playback?.repeatState {
        case "context": .track
        case "track": .off
        default: .context
        }
    }
}

private struct PlaybackProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.55))
                        .frame(width: geometry.size.width * (configuration.fractionCompleted ?? 0))
                }
        }.frame(height: 3)
    }
}
