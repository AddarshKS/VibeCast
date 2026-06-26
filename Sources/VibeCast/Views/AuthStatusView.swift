import SwiftUI

struct AuthStatusView: View {
    @ObservedObject var store: VibeCastStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: store.authState.isLoggedIn ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(store.authState.isLoggedIn ? .green : .secondary)

            Text(store.authState.displayText)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            if store.authState.isLoggedIn {
                Button("Logout") {
                    store.logout()
                }
                .controlSize(.small)
                .disabled(store.authState.isBusy)
            } else {
                Button("Login") {
                    store.login()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(store.authState.isBusy)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
