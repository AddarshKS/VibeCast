import SwiftUI

struct PlayerDetailsView: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    @ObservedObject var details: PlayerDetailsStore
    @ObservedObject var settings: AppSettings
    let panel: PlayerPanel
    var focusLyrics: (() -> Void)? = nil
    var focused = false
    var lyricsHeight: CGFloat = 250
    var queueViewportHeight: CGFloat = 300
    var queueActivation = 0
    static let queueStartID = "queue-up-next"
    @State private var retry = 0
    @State private var handledRetry = 0
    @State private var hintHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: density.detailSpacing) {
            if panel == .queue {
                recentlyPlayed
                VStack(alignment: .leading, spacing: density.detailSpacing) {
                    header.id(Self.queueStartID)
                        .background(QueueScrollBehavior(resetRevision: retry, activation: queueActivation,
                                                        historyCount: details.recentlyPlayed.count))
                    queue
                }
                .frame(minHeight: queueViewportHeight, alignment: .top)
            } else {
                if !focused { header }
                if focused {
                    if case .loaded(.synced) = details.lyrics, settings.lyricsEnabled, store.playback?.item != nil {
                        lyrics
                    } else {
                        ScrollView { lyrics.frame(maxWidth: .infinity, alignment: .leading) }
                            .scrollIndicators(.never).frame(height: lyricsHeight)
                    }
                } else { lyrics }
            }
        }
        .task(id: panel == .queue ? "queue|\(retry)" : "lyrics|\(store.playback?.item?.uri ?? "")|\(settings.lyricsEnabled)|\(retry)") {
            let force = retry != handledRetry
            handledRetry = retry
            if panel == .lyrics {
                await details.loadLyrics(for: store.playback?.item, enabled: settings.lyricsEnabled, force: force)
            } else {
                while !Task.isCancelled {
                    if !store.isBusy {
                        await store.refreshPlayback()
                        guard !Task.isCancelled else { return }
                        await details.refreshQueue()
                        guard !Task.isCancelled else { return }
                    }
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: density.value(8, 4)) {
            Text(panel == .queue ? "Up Next" : "Lyrics")
                .font(.system(size: density.value(15, 13), weight: .semibold)).fixedSize()
            if panel == .lyrics {
                Link("By LRCLIB", destination: URL(string: "https://lrclib.net")!)
                    .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
            }
            Spacer(minLength: 4)
            if panel == .lyrics, let focusLyrics {
                HStack(spacing: density.value(8, 4)) {
                    HStack(spacing: 3) {
                        Text("Try this!")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
                    LyricsModeButton(hintHovered: hintHovered, action: focusLyrics)
                        .measureWandPosition("normal")
                }
                .contentShape(Rectangle())
                .onHover { hintHovered = $0 }
            }
            if store.pendingQueueIndex != nil || store.pendingHistoryIndex != nil {
                PlayerIconButton(title: "Stop moving through songs", symbol: "stop.fill") { store.cancel() }
            } else {
                PlayerIconButton(title: "Refresh", symbol: "arrow.clockwise") {
                    retry += 1
                }
                    .disabled(store.isBusy)
            }
        }
    }

    @ViewBuilder private var recentlyPlayed: some View {
        if !details.recentlyPlayed.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recently Played")
                    .font(.system(size: density.value(15, 13), weight: .semibold))
                    .padding(.bottom, density.detailSpacing)
                songRows(details.recentlyPlayed.map(\.queueItem), list: .history)
                Divider().opacity(0.35).padding(.top, density.detailSpacing)
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
                songRows(items, list: .upcoming)
            }
        }
    }

    private func songRows(_ items: [SpotifyQueueItem], list: PlayerList) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                QueueSongButton(item: item, index: index, busy: store.isBusy,
                                pending: (list == .upcoming ? store.pendingQueueIndex : store.pendingHistoryIndex) == index) {
                    store.playListItem(at: index, in: items, list: list)
                }
                .padding(.vertical, density.value(9, 6))
                if index < items.count - 1 { Divider().opacity(0.35).padding(.leading, 26) }
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
                SyncedLyricsView(store: store, lyrics: timed, trackURI: details.lyricsTrackURI,
                                 height: lyricsHeight).id(details.lyricsTrackURI)
            case .loaded(.text(let text)):
                Text("Timing unavailable for this recording").font(.caption).foregroundStyle(.secondary)
                Text(text).font(.system(size: density.lyricsFont, weight: .semibold, design: .rounded))
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
                Text(item.durationText).font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
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
