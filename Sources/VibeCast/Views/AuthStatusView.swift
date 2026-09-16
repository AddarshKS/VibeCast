import SwiftUI

struct AuthStatusView: View {
    @ObservedObject var store: VibeCastStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "headphones").font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.teal).padding(.top, 12).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your music.\nYour moment.")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Connect your Spotify account.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            if store.authState.isBusy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(store.authState == .authenticating ? "Waiting for Spotify..." : "Checking your connection...")
                        .font(.callout)
                    Spacer()
                    if store.authState == .authenticating {
                        Button("Cancel") { store.cancel() }.buttonStyle(.borderless)
                    }
                }
            } else {
                Button { store.login() } label: {
                    HStack {
                        Text("Connect Spotify")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.vertical, 5)
                }
                .modifier(PrimaryMusicButton())
                .controlSize(.large)
            }
            Text("Playback requires Spotify Premium. Your login stays in your Mac's Keychain.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
    }
}
