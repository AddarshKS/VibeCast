import SwiftUI

struct PromptComposerView: View {
    @Environment(\.playerDensity) private var density
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: VibeCastStore
    var beforeSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Music request", text: $store.prompt,
                      prompt: Text("Let's cast your vibe!").foregroundColor(hovered ? hoverText : .secondary), axis: .vertical)
                .font(.system(size: 13)).textFieldStyle(.plain)
                .foregroundStyle(hovered ? hoverText : Color.primary.opacity(0.85))
                .lineLimit(1...3).focused($focused)
                .fixedSize(horizontal: false, vertical: true)
                .onSubmit { submit() }
                .accessibilityLabel("Music request")
                .background(ComposerFocusBoundary(focused: $focused))
            Button { if store.showsRequestProgress { store.cancel() } else { submit() } } label: {
                Image(systemName: store.showsRequestProgress ? "stop.fill" : "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSend ? Color(nsColor: .windowBackgroundColor) : Color.secondary)
                    .frame(width: density.value(30, 26), height: density.value(30, 26))
                    .background(canSend ? Color.primary : Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain).disabled(!canSend)
            .help(store.showsRequestProgress ? "Cancel request" : "Send request")
            .accessibilityLabel(store.showsRequestProgress ? "Cancel request" : "Send request")
        }
        .padding(.leading, density.value(13, 10)).padding(.trailing, 8).padding(.vertical, density.value(9, 6))
        .background { if hovered { ControlHoverGlow() } }
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(focused ? Color.teal.opacity(0.8) : Color.primary.opacity(hovered ? 0.15 : 0.3), lineWidth: 1)
            .allowsHitTesting(false))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .onAppear { focused = false }
    }

    private var hoverText: Color { colorScheme == .dark ? .white : .primary }

    private var canSend: Bool { store.showsRequestProgress || (!store.isBusy && !store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    private func submit() {
        guard !store.isBusy, !store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        beforeSubmit()
        focused = false
        store.submitPrompt()
    }
}
