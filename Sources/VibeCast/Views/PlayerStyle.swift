import SwiftUI

struct RaisedPlayerSurface: ViewModifier {
    var artworkURL: URL? = nil
    func body(content: Content) -> some View {
        content
            .modifier(ArtworkAccent(url: artworkURL, panel: true))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.24), .primary.opacity(0.05), .white.opacity(0.09)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 5)
    }
}

struct LyricsModeButton: View {
    var active = false
    var hintHovered = false
    var action: () -> Void

    var body: some View {
        PlayerIconButton(title: active ? "Exit Lyrics Mode" : "Enter Lyrics Mode",
                         symbol: "sparkles", active: active, symbolSize: 16,
                         externallyHovered: hintHovered, pulsesOnHover: !active, action: action)
    }
}

struct PlayerWindowButton: View {
    let detached: Bool
    var action: () -> Void
    var body: some View {
        PlayerIconButton(title: detached ? "Return to menu bar" : "Open player window",
                         symbol: detached ? "pip.exit" : "pip.enter", active: detached, action: action)
    }
}

struct AlbumArtworkButton: View {
    let url: URL?
    let size: CGFloat
    var miniplayer = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            CoverArtwork(url: url, size: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(hovered ? 0.35 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 5, y: 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(miniplayer ? "Return to player" : "Open miniplayer")
        .accessibilityLabel(miniplayer ? "Return to player" : "Open miniplayer")
    }
}

struct PlayerIconButton: View {
    @Environment(\.playerDensity) private var density
    let title: String
    let symbol: String
    var active = false
    var pending = false
    var symbolSize: CGFloat = 13
    var externallyHovered = false
    var pulsesOnHover = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol).opacity(pending ? 0 : 1)
                if pending { ProgressView().controlSize(.mini) }
            }
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(active ? Color.teal : Color.primary.opacity(0.8))
                .frame(width: density.buttonSize, height: density.buttonSize)
                .background(active ? Color.teal.opacity(0.13) : Color.primary.opacity(hovered || externallyHovered ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6))
                .background {
                    if pulsesOnHover && (hovered || externallyHovered) {
                        ControlHoverGlow(style: .pulse, cornerRadius: 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
