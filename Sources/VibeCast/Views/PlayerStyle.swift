import SwiftUI

struct RaisedPlayerSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var title: String { active ? "Exit Lyrics Mode" : "Enter Lyrics Mode" }

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.primary)
                .shadow(color: .primary.opacity(hovered ? 0.45 : 0), radius: 4)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(hovered ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        .help(title).accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct PlayerIconButton: View {
    let title: String
    let symbol: String
    var active = false
    var pending = false
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol).opacity(pending ? 0 : 1)
                if pending { ProgressView().controlSize(.mini) }
            }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? Color.teal : Color.primary.opacity(0.8))
                .frame(width: 30, height: 30)
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
