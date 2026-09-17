import SwiftUI

struct ReadingPlayerView: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    let panel: PlayerPanel
    var toggleMiniplayer: () -> Void
    var toggleWindow: () -> Void
    var selectPanel: (PlayerPanel?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SongIdentityView(store: store, compact: true, artworkAction: toggleMiniplayer,
                                 draggable: presentation.isDetached)
                PlayerWindowButton(detached: presentation.isDetached, action: toggleWindow)
            }
            .padding(.horizontal, density.inset).padding(.vertical, density.value(18, 12))
            .fixedSize(horizontal: false, vertical: true)
            ReadingHeaderDivider().padding(.horizontal, density.inset)
            GeometryReader { geometry in
                if panel == .queue {
                    ScrollView(.vertical, showsIndicators: false) {
                        PlayerDetailsView(store: store, details: store.playerDetails, settings: store.settings,
                                          panel: .queue, queueViewportHeight: geometry.size.height,
                                          queueActivation: presentation.queueActivation)
                            .padding(.horizontal, density.value(24, 16))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .scrollIndicators(.never)
                } else {
                    PlayerDetailsView(store: store, details: store.playerDetails, settings: store.settings,
                                      panel: .lyrics, lyricsHeight: geometry.size.height)
                        .padding(.horizontal, density.value(24, 16))
                }
            }
            .clipped()
            VStack(spacing: 10) {
                if store.latestError != nil { RequestStatusView(store: store) }
                PlaybackControlsView(store: store, panel: Binding(get: { panel }, set: { selectPanel($0) }))
            }
            .padding(.horizontal, density.value(36, 26)).padding(.top, density.value(14, 10)).padding(.bottom, density.value(16, 12))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if presentation.isDetached { WindowResizeHint().padding(6) }
        }
    }
}

struct ReadingHeaderDivider: View {
    var body: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
