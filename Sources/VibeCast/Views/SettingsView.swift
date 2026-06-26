import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: VibeCastStore

    var body: some View {
        Form {
            LabeledContent("Spotify client ID", value: AppConfig.spotifyClientID)
            LabeledContent("Redirect URI", value: AppConfig.spotifyRedirectURI)
            LabeledContent("Login status", value: store.authState.displayText)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }
}
