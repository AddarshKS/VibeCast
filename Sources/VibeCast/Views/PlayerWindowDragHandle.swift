import SwiftUI

struct PlayerWindowDragHandle: View {
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4) { _ in
                VStack(spacing: 3) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                }
            }
        }
        .foregroundStyle(.primary.opacity(hovered ? 1 : 0.6))
        .frame(width: 44, height: 20)
        .background(.black.opacity(hovered ? 0.3 : 0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(SettingsDragRegion())
        .onHover { hovered = $0 }
        .help("Move player window")
        .accessibilityElement(children: .ignore).accessibilityLabel("Move player window")
    }
}
