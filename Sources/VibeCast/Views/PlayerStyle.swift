import SwiftUI

struct InspirationButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovered ? Color.white : Color.primary)
            // Apply one glow to the resolved label, not separate symbol layers.
            .compositingGroup()
            .shadow(color: .white.opacity(hovered ? 0.35 : 0), radius: 4)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct RaisedPlayerSurface: ViewModifier {
    var artworkURL: URL? = nil
    func body(content: Content) -> some View {
        content
            .modifier(ArtworkAccent(url: artworkURL))
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
        .help("Open miniplayer")
        .accessibilityLabel("Open miniplayer")
    }
}

struct PlayerIconButton: View {
    @Environment(\.playerDensity) private var density
    let title: String
    let symbol: String
    var active = false
    var pending = false
    var symbolSize: CGFloat = 13
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
                .background(active ? Color.teal.opacity(0.13) : Color.primary.opacity(hovered ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
