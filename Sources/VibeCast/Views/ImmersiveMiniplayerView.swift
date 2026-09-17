import SwiftUI

// Only the upper artwork is an exit button. Neither the controls nor the padded
// PiP corner are descendants of that button, so their clicks cannot dismiss it.
struct ImmersiveMiniplayerView: View {
    @Environment(\.playerDensity) private var density
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    var toggleMiniplayer: () -> Void
    var toggleWindow: () -> Void
    var selectPanel: (PlayerPanel?) -> Void
    @State private var controlsHeight: CGFloat = 108

    private var size: CGFloat { density.width }
    private var exitHeight: CGFloat { max(0, size - 12 - controlsHeight - 8) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ImmersiveArtworkView(url: store.playback?.item?.resolvedTrack.artworkURL, size: size)
                    .measureRippleOrigin("mini-album")

                Button(action: toggleMiniplayer) {
                    Color.clear.frame(width: size, height: exitHeight)
                        .contentShape(ImmersiveArtworkExitArea(reservesDragHandle: presentation.isDetached))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Return to player")
                .help("Return to player")

                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    VStack(spacing: 3) {
                        Text(store.playback?.item?.name ?? "Nothing playing")
                            .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                            .foregroundStyle(.primary)
                        Text(store.playback?.item?.resolvedTrack.artist ?? "Choose a song in Spotify")
                            .font(.system(size: 11)).lineLimit(1).foregroundStyle(.primary.opacity(0.85))
                    }
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .allowsHitTesting(false)
                    PlaybackControlsView(store: store,
                        panel: Binding(get: { presentation.panel }, set: { selectPanel($0) }),
                        selectPanel: { selectPanel($0) })
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: ImmersiveControlsHeight.self, value: geometry.size.height)
                        })
                }
                .padding(12)
                .onPreferenceChange(ImmersiveControlsHeight.self) { height in
                    if height > 0, abs(controlsHeight - height) > 0.5 { controlsHeight = height }
                }

                PlayerWindowButton(detached: presentation.isDetached, action: toggleWindow)
                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: ImmersiveArtworkExitArea.cornerSize, height: ImmersiveArtworkExitArea.cornerSize)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if presentation.isDetached {
                    PlayerWindowDragHandle().padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .frame(width: size, height: size)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background {
                if presentation.isDetached { SettingsDragRegion().accessibilityHidden(true) }
            }
            if store.latestError != nil {
                RequestStatusView(store: store).padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ImmersiveArtworkExitArea: Shape {
    static let cornerSize: CGFloat = 52
    var reservesDragHandle = false

    func path(in rect: CGRect) -> Path {
        let corner = min(Self.cornerSize, rect.width, rect.height)
        var path = Path()
        if reservesDragHandle {
            let grip = CGRect(x: rect.midX - 26, y: rect.minY, width: 52, height: 30)
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: max(0, grip.minX - rect.minX), height: corner))
            path.addRect(CGRect(x: grip.maxX, y: rect.minY, width: max(0, rect.maxX - corner - grip.maxX), height: corner))
            path.addRect(CGRect(x: grip.minX, y: grip.maxY, width: grip.width, height: max(0, corner - grip.height)))
        } else {
            path.addRect(CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width - corner), height: corner))
        }
        path.addRect(CGRect(x: rect.minX, y: rect.minY + corner, width: rect.width, height: max(0, rect.height - corner)))
        return path
    }
}

private struct ImmersiveControlsHeight: PreferenceKey {
    static let defaultValue: CGFloat = 108
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
