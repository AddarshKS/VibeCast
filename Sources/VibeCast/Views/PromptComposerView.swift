import SwiftUI

struct PromptComposerView: View {
    @ObservedObject var store: VibeCastStore
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Play Animals by Martin Garrix", text: $store.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($isPromptFocused)
                .onSubmit {
                    store.submitPrompt()
                }
                .padding(10)
                .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    store.submitPrompt()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    store.clear()
                    isPromptFocused = true
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .onAppear {
            isPromptFocused = true
        }
    }
}
