import SwiftUI

struct MiniplayerDetailsView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    let panel: PlayerPanel
    var close: () -> Void
    var toggleWindow: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.playback?.item?.name ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(store.playback?.item?.resolvedTrack.artist ?? "Choose a song in Spotify")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    if presentation.isDetached { SettingsDragRegion().accessibilityHidden(true) }
                }
                Group {
                    if panel == .lyrics { PlayerIconButton(title: "Close miniplayer lyrics", symbol: "quote.bubble", active: true, action: close) }
                    else { PlayerIconButton(title: "Close miniplayer queue", symbol: "list.bullet", active: true, action: close) }
                }
                .measureRippleOrigin("mini-\(panel.rawValue)-exit")
                PlayerWindowButton(detached: presentation.isDetached, action: toggleWindow)
            }
            .padding(.horizontal, 12).padding(.top, presentation.isDetached ? 22 : 12)
            .padding(.bottom, 3)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .bottom) { ReadingHeaderDivider().padding(.horizontal, 12).offset(y: 3) }
            GeometryReader { geometry in
                if panel == .queue {
                    ScrollView(.vertical, showsIndicators: false) {
                        PlayerDetailsView(store: store, details: store.playerDetails, settings: store.settings,
                                          panel: .queue, queueViewportHeight: geometry.size.height,
                                          queueActivation: presentation.miniplayerQueueActivation,
                                          overArtwork: true)
                            .padding(.horizontal, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .scrollIndicators(.never)
                } else {
                    PlayerDetailsView(store: store, details: store.playerDetails, settings: store.settings,
                                      panel: .lyrics, lyricsHeight: geometry.size.height,
                                      overArtwork: true)
                        .padding(.horizontal, 12)
                }
            }
            .clipped()
            if store.latestError != nil { RequestStatusView(store: store).padding(.horizontal, 12) }
        }
        .padding(.bottom, 3)
        .frame(width: PlayerPresentation.width, height: presentation.miniplayerDetailHeight)
        .background {
            ImmersiveArtworkView(url: store.playback?.item?.resolvedTrack.artworkURL,
                                 size: PlayerPresentation.width, reading: true, height: presentation.miniplayerDetailHeight)
        }
        .overlay(alignment: .top) {
            if presentation.isDetached { PlayerWindowDragHandle().padding(.top, 2) }
        }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WindowResizeHint: View {
    var body: some View {
        Canvas { context, size in
            var lines = Path()
            lines.move(to: CGPoint(x: 1, y: size.height - 1))
            lines.addLine(to: CGPoint(x: size.width - 1, y: 1))
            lines.move(to: CGPoint(x: 7, y: size.height - 1))
            lines.addLine(to: CGPoint(x: size.width - 1, y: 7))
            context.stroke(lines, with: .color(.secondary.opacity(0.65)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        .frame(width: 12, height: 12)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
