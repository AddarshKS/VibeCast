import SwiftUI

struct NowPlayingView: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    @Binding var panel: PlayerPanel?
    var detached = false
    var toggleWindow: () -> Void = {}
    var toggleMiniplayer: () -> Void = {}

    var body: some View {
        VStack(spacing: density.value(10, 8)) {
            HStack(alignment: .top, spacing: 4) {
                SongIdentityView(store: store, artworkAction: toggleMiniplayer)
                PlayerWindowButton(detached: detached, action: toggleWindow)
            }
            PlaybackControlsView(store: store, panel: $panel)
        }
        .padding(density.value(16, 12))
        .modifier(RaisedPlayerSurface(artworkURL: store.playback?.item?.resolvedTrack.artworkURL))
    }
}

struct SongIdentityView: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    var compact = false
    var artworkAction: (() -> Void)? = nil
    var draggable = false

    var body: some View {
            HStack(spacing: density.value(14, 10)) {
                if let artworkAction {
                    AlbumArtworkButton(url: store.playback?.item?.resolvedTrack.artworkURL,
                                       size: compact ? 40 : density.value(64, 48), action: artworkAction)
                        .measureWandPosition("album")
                } else {
                    CoverArtwork(url: store.playback?.item?.resolvedTrack.artworkURL, size: compact ? 40 : density.value(64, 48))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                }
                VStack(alignment: .leading, spacing: density.value(5, 3)) {
                    if !compact {
                        Text(store.playback?.isPlaying == true ? "NOW PLAYING" : (store.playback?.item == nil ? "YOUR SPOTIFY" : "PAUSED"))
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Text(store.playback?.item?.name ?? (store.playback?.isPlaying == true ? "Playing on Spotify" : "Nothing playing"))
                        .font(.system(size: compact ? 14 : density.value(17, 15), weight: .semibold)).lineLimit(compact ? 1 : 2)
                    Text(store.playback?.item?.resolvedTrack.artist ?? (store.playback?.isPlaying == true ? "Open Spotify for this item." : "Choose your next song."))
                        .font(.system(size: density.value(12, 11))).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if draggable { SettingsDragRegion().accessibilityHidden(true) }
                }
            }
    }
}

struct PlaybackControlsView: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    @Binding var panel: PlayerPanel?
    var selectPanel: ((PlayerPanel) -> Void)? = nil

    var body: some View {
        VStack(spacing: density.value(10, 7)) {
            if let duration = store.playback?.item?.durationMS, duration > 0 {
                PlaybackSeekBar(store: store)
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
                        .frame(width: density.value(42, 38), height: density.value(42, 38))
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
    }

    private func toggle(_ value: PlayerPanel) {
        if let selectPanel { selectPanel(value) }
        else { panel = panel == value ? nil : value }
    }
    private var transportPending: Bool { store.pendingPlayerAction == .pause || store.pendingPlayerAction == .resume }
    private var nextRepeat: SpotifyRepeatMode {
        switch store.playback?.repeatState {
        case "context": .track
        case "track": .off
        default: .context
        }
    }
}
