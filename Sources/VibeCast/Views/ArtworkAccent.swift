import SwiftUI

struct ArtworkAccent: ViewModifier {
    let url: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tint: ArtworkTint?

    func body(content: Content) -> some View {
        content.background {
            let color = tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .teal
            RoundedRectangle(cornerRadius: 8).fill(color.opacity(tint == nil ? 0.08 : 0.30))
        }
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.4), value: tint)
        .task(id: url) {
            guard let url else { tint = nil; return }
            let result = await ArtworkPalette.shared.tint(for: url)
            guard !Task.isCancelled else { return }
            tint = result
        }
    }
}
