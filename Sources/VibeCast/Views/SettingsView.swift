import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var subscription: ChatGPTSession
    @Environment(\.dismiss) private var dismiss
    private var close: (() -> Void)?
    @State private var draft: SettingsDraft
    @State(initialValue: "") private var apiKey: String
    @State(initialValue: false) private var advanced: Bool
    @State(initialValue: false) private var saved: Bool

    init(store: VibeCastStore, settings: AppSettings, close: (() -> Void)? = nil) {
        self.store = store
        self.settings = settings
        self.subscription = store.chatGPT
        self._draft = State(initialValue: SettingsDraft(settings: settings))
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 22, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .background(SettingsDragRegion())
                PlayerIconButton(title: "Close settings", symbol: "xmark") {
                    if let close { close() } else { dismiss() }
                }
            }
            .padding(20)
            Form {
                Section("Spotify") {
                    LabeledContent("Account", value: store.authState.displayText)
                    if store.authState.isLoggedIn {
                        Button("Disconnect Spotify", role: .destructive) { store.logout() }
                    } else {
                        Button("Connect Spotify") { store.login() }
                    }
                }
                Section("Cast Magic") {
                    Toggle("Enable Cast Magic", isOn: $draft.aiConsent)
                    Text("Your musical requests are sent to OpenAI to curate songs. Spotify listening history, search results, and credentials are never included in AI prompts.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("AI connection", selection: $draft.provider) {
                        ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(store.isBusy || subscription.isBusy)
                    if draft.provider == .chatGPT {
                        ChatGPTConnectionView(session: store.chatGPT, model: $draft.subscriptionModel, requestBusy: store.isBusy)
                    } else if draft.provider == .personalAPI {
                        SecureField("API key", text: $apiKey, prompt: Text("Leave blank to keep saved key"))
                        TextField("Model", text: $draft.model)
                        Text("API usage is billed to your OpenAI API account, separately from ChatGPT.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Remove saved key", role: .destructive) { store.removeAPIKey() }
                    } else {
                        Text("Uses the publisher's hosted AI service. Your ChatGPT subscription does not cover API usage.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Notifications") {
                    Toggle("Playlist recommendations", isOn: $draft.notificationsEnabled)
                    Button("Notification settings...") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
                Section("Lyrics") {
                    Toggle("Use LRCLIB", isOn: $draft.lyricsEnabled)
                    Text("Song title, artist, album and duration are shared with LRCLIB only while the lyrics panel is open. No Spotify credentials are shared.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                AdvancedSettingsSection(draft: $draft, isExpanded: $advanced)
                if let error = store.latestError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                if saved && !hasChanges { Text("Saved").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Save changes") {
                    saved = store.saveSettings(draft, apiKey: apiKey)
                    if saved {
                        draft = SettingsDraft(settings: settings)
                        apiKey = ""
                    }
                }
                .modifier(SettingsSaveButton())
                .disabled(!hasChanges || store.isBusy || subscription.isBusy || !draft.isValid)
            }
            .padding(20)
        }
        .frame(minWidth: 500, idealWidth: 520, maxWidth: .infinity, minHeight: 620, idealHeight: 680, maxHeight: .infinity)
        .modifier(SettingsGlass())
        .modifier(SettingsFirstClick())
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)).allowsHitTesting(false))
        .tint(.teal)
        .onAppear {
            draft = SettingsDraft(settings: settings)
            apiKey = ""
            saved = false
        }
        .onChange(of: settings.lyricsEnabled) { old, new in
            // Lyrics can also be enabled from the player while Settings stays open.
            if draft.lyricsEnabled == old { draft.lyricsEnabled = new }
        }
    }

    private var hasChanges: Bool { draft.hasChanges(from: settings, apiKey: apiKey) }
}

struct AdvancedSettingsSection: View {
    @Binding var draft: SettingsDraft
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            if isExpanded {
                TextField("Spotify client ID", text: $draft.clientID)
                TextField("VibeCast service", text: $draft.serviceAddress, prompt: Text("https://your-service.example"))
                LabeledContent("Codex executable") {
                    HStack(spacing: 8) {
                        TextField("Codex executable", text: $draft.codexExecutable, prompt: Text("Automatic"))
                            .labelsHidden()
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select Codex"
                            if panel.runModal() == .OK { draft.codexExecutable = panel.url?.path ?? "" }
                        } label: { Image(systemName: "folder") }
                        .help("Choose Codex executable").accessibilityLabel("Choose Codex executable")
                    }
                }
                LabeledContent("Spotify redirect", value: AppConfig.spotifyRedirectURI).textSelection(.enabled)
                Text("Changing connections signs you out. Register the redirect URL in the Spotify developer dashboard.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Version", value: AppConfig.version)
            }
        } header: {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced")
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Show or hide advanced connection settings")
        }
    }
}

private struct SettingsSaveButton: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(PrimaryMusicButton())
        } else {
            content.buttonStyle(.bordered).foregroundStyle(.secondary)
        }
    }
}

private struct ChatGPTConnectionView: View {
    @ObservedObject var session: ChatGPTSession
    @Binding var model: String
    let requestBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let account = session.account {
                Text(account.displayName).font(.callout).textSelection(.enabled)
                Picker("Model", selection: $model) {
                    Text("Account default").tag("")
                    ForEach(session.models) { Text($0.displayName).tag($0.model) }
                }
                .disabled(session.isBusy || requestBusy)
                if let remaining = session.usage?.core?.remaining {
                    Text("Included allowance: \(remaining)% remaining").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Disconnect ChatGPT") { session.signOut() }
                    Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Refresh connection").accessibilityLabel("Refresh connection")
                }
                .disabled(session.isBusy || requestBusy)
            } else if session.isSigningIn {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for ChatGPT...").font(.callout)
                    Spacer()
                    Button("Cancel") { session.cancelSignIn() }
                }
            } else {
                Button("Sign in with ChatGPT") { session.signIn() }
                    .disabled(session.isBusy || requestBusy)
            }
            Text("Uses your ChatGPT allowance through local Codex, with no API-key fallback. Limits are shared with your other Codex usage.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = session.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                Link("Codex setup", destination: URL(string: "https://learn.chatgpt.com/docs/cli")!)
                    .font(.caption)
            }
        }
        .task { await session.refresh() }
    }
}
