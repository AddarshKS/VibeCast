import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: VibeCastStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            AuthStatusView(store: store)
            PromptComposerView(store: store)
            RequestStatusView(store: store)
            DiagnosticsView(store: store)
            Divider()
            RouteReadinessView()
        }
        .padding(16)
        .background(.regularMaterial)
        .task {
            SpotifyCallbackRouter.shared.register(store: store)
        }
        .onOpenURL { url in
            SpotifyCallbackRouter.shared.handle(url: url)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("VibeCast")
                    .font(.headline)
                Text("Smart Spotify assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit VibeCast")
        }
    }
}
