import SwiftUI

struct PlayerDetailsView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var details: PlayerDetailsStore
    @ObservedObject var settings: AppSettings
    let panel: PlayerPanel
    var close: () -> Void
    @State private var retry = 0
    @State private var handledRetry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panel == .queue ? "Up next" : "Lyrics").font(.system(size: 15, weight: .semibold))
                Spacer()
                if panel == .lyrics && settings.lyricsEnabled {
                    Link("LRCLIB", destination: URL(string: "https://lrclib.net")!)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if store.pendingQueueIndex != nil {
                    PlayerIconButton(title: "Stop advancing queue", symbol: "stop.fill") { store.cancel() }
                } else {
                    PlayerIconButton(title: "Refresh", symbol: "arrow.clockwise") { retry += 1 }
                        .disabled(store.isBusy)
                }
                PlayerIconButton(title: "Close \(panel.rawValue)", symbol: "xmark", action: close)
            }
            if panel == .queue { queue } else { lyrics }
        }
        .task(id: "\(panel.rawValue)|\(store.playback?.item?.uri ?? "")|\(settings.lyricsEnabled)|\(retry)") {
            let force = retry != handledRetry
            handledRetry = retry
            if panel == .lyrics {
                await details.loadLyrics(for: store.playback?.item, enabled: settings.lyricsEnabled, force: force)
            } else {
                while !Task.isCancelled {
                    if !store.isBusy { await details.refreshQueue() }
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                }
            }
        }
    }

    @ViewBuilder private var queue: some View {
        switch details.queue {
        case .idle, .loading: loading("Loading queue")
        case .failed(let message): failure(message)
        case .loaded(let items):
            if items.isEmpty { empty("Your queue is clear.", detail: "Start a song or playlist in Spotify.") }
            else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            QueueSongButton(item: item, index: index, busy: store.isBusy,
                                            pending: store.pendingQueueIndex == index) {
                                store.playQueueItem(at: index, in: items)
                            }
                            if let url = item.spotifyURL {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right").font(.system(size: 10)).frame(width: 24, height: 28)
                                }
                                .foregroundStyle(.secondary)
                                .help("Open \(item.name) in Spotify").accessibilityLabel("Open \(item.name) in Spotify")
                            }
                        }
                        .padding(.vertical, 9)
                        if index < items.count - 1 { Divider().opacity(0.35).padding(.leading, 26) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var lyrics: some View {
        if !settings.lyricsEnabled {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lyrics from LRCLIB").font(.system(size: 14, weight: .medium))
                Text("When this panel is open, the song title, artist, album and duration are sent to LRCLIB. Your Spotify account and credentials are never shared.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Enable lyrics") { settings.lyricsEnabled = true }.buttonStyle(.bordered)
            }
        } else if store.playback?.item == nil {
            empty("No song playing.", detail: "Lyrics will appear when a song is playing.")
        } else {
            switch details.lyrics {
            case .idle, .loading: loading("Finding lyrics")
            case .failed(let message): failure(message)
            case .loaded(.unavailable): empty("No lyrics for this song.", detail: "This recording isn't available on LRCLIB.")
            case .loaded(.instrumental): empty("Just the music.", detail: "This recording is instrumental.")
            case .loaded(.synced(let timed)):
                SyncedLyricsView(store: store, lyrics: timed, trackURI: details.lyricsTrackURI).id(details.lyricsTrackURI)
            case .loaded(.text(let text)):
                Text("Timing unavailable for this recording").font(.caption).foregroundStyle(.secondary)
                Text(text).font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineSpacing(9).foregroundStyle(.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 16)
            }
        }
    }

    private func loading(_ title: String) -> some View {
        HStack(spacing: 10) { ProgressView().controlSize(.small); Text(title).font(.caption).foregroundStyle(.secondary) }
            .padding(.vertical, 16)
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(.vertical, 12)
    }
    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Try again") { retry += 1 }.buttonStyle(.bordered)
        }
    }
}

private struct QueueSongButton: View {
    let item: SpotifyQueueItem
    let index: Int
    let busy: Bool
    let pending: Bool
    let play: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                ZStack {
                    if pending { ProgressView().controlSize(.mini) }
                    else if hovered && item.playableTrack != nil { Image(systemName: "play.fill") }
                    else { Text(String(index + 1)).monospacedDigit() }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 16, height: 20)
                CoverArtwork(url: item.artworkURL, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || item.playableTrack == nil || index >= 20)
        .onHover { hovered = $0 }
        .help("Play \(item.name)")
        .accessibilityLabel("Play \(item.name) by \(item.subtitle)")
    }
}
