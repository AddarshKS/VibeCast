import SwiftUI

struct PromptComposerView: View {
    @ObservedObject var store: VibeCastStore
    var beforeSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("What sounds good?", text: $store.prompt, axis: .vertical)
                .font(.system(size: 13)).textFieldStyle(.plain)
                .lineLimit(1...3).focused($focused)
                .fixedSize(horizontal: false, vertical: true)
                .onSubmit { submit() }
                .accessibilityLabel("Music request")
            Button { if store.showsRequestProgress { store.cancel() } else { submit() } } label: {
                Image(systemName: store.showsRequestProgress ? "stop.fill" : "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSend ? Color(nsColor: .windowBackgroundColor) : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(canSend ? Color.primary : Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain).disabled(!canSend)
            .help(store.showsRequestProgress ? "Cancel request" : "Send request")
            .accessibilityLabel(store.showsRequestProgress ? "Cancel request" : "Send request")
        }
        .padding(.leading, 13).padding(.trailing, 8).padding(.vertical, 9)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Color.teal.opacity(0.45) : Color.primary.opacity(0.12), lineWidth: 0.75))
        .onAppear { focused = true }
    }

    private var canSend: Bool { store.showsRequestProgress || (!store.isBusy && !store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    private func submit() {
        guard !store.isBusy, !store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        beforeSubmit()
        store.submitPrompt()
    }
}
