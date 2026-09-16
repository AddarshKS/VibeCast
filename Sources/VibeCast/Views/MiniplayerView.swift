import SwiftUI

struct MiniplayerView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    var toggleMiniplayer: () -> Void
    var toggleWindow: () -> Void
    var selectPanel: (PlayerPanel?) -> Void

    private var artworkURL: URL? { store.playback?.item?.resolvedTrack.artworkURL }

    var body: some View {
        VStack(spacing: 10) {
            AlbumArtworkButton(url: artworkURL, size: 192, miniplayer: true, action: toggleMiniplayer)
                .measureWandPosition("mini-album")
            VStack(spacing: 3) {
                Text(store.playback?.item?.name ?? "Nothing playing")
                    .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                Text(store.playback?.item?.resolvedTrack.artist ?? "Choose a song in Spotify")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .overlay {
                if presentation.isDetached { SettingsDragRegion().accessibilityHidden(true) }
            }
            PlaybackControlsView(store: store, panel: Binding(get: { presentation.panel }, set: { selectPanel($0) }),
                                 selectPanel: { selectPanel($0) })
            if store.latestError != nil { RequestStatusView(store: store) }
        }
        .padding(.horizontal, 26).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .modifier(ArtworkAccent(url: artworkURL))
        .overlay(alignment: .top) {
            if presentation.isDetached { SettingsDragRegion().frame(height: 12).accessibilityHidden(true) }
        }
        .overlay(alignment: .topTrailing) {
            PlayerWindowButton(detached: presentation.isDetached, action: toggleWindow).padding(8)
        }
    }
}
