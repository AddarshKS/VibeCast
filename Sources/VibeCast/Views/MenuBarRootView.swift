import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wandPositions: [String: CGPoint] = [:]
    @State private var rippleOrigin = CGPoint(x: 100, y: 300)
    @State private var measurements: [String: CGFloat] = [:]
    var maximumHeight: CGFloat = 680
    var resize: (CGFloat) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var toggleWindow: () -> Void = {}

    init(store: VibeCastStore, developerView: Bool = false, panel: PlayerPanel? = nil,
         maximumHeight: CGFloat = 680, resize: @escaping (CGFloat) -> Void = { _ in },
         openSettings: @escaping () -> Void = {}, presentation: PlayerPresentation = PlayerPresentation(),
         toggleWindow: @escaping () -> Void = {}) {
        self.store = store
        self.presentation = presentation
        self.toggleWindow = toggleWindow
        self.openSettings = openSettings
        if developerView { presentation.advanced = true }
        if let panel { presentation.panel = panel }
        self.maximumHeight = maximumHeight
        self.resize = resize
    }

    var body: some View {
        ZStack(alignment: .top) {
            if focused {
                focusedPlayer.transition(lyricsTransition).zIndex(1)
            } else {
                normalPlayer.transition(lyricsTransition).zIndex(0)
            }
        }
        // AppKit owns the outer height. Pin content to its top even during the
        // frame between a SwiftUI state change and the native popover resize.
        .frame(width: 400)
        .frame(maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "player")
        .modifier(DetachedPlayerSurface(enabled: presentation.isDetached))
        .tint(.teal)
        .onPreferenceChange(WandPositions.self) { value in
            wandPositions.merge(value, uniquingKeysWith: { _, latest in latest })
        }
        .onPreferenceChange(PanelMeasurements.self) { value in
            if !focused && !value.isEmpty && value != measurements { measurements = value }
        }
        .onChange(of: totalHeight, initial: true) { _, height in resize(height) }
        .onChange(of: store.prompt) { _, _ in store.noteInteraction() }
        .onChange(of: panel) { _, _ in store.noteInteraction() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if !advanced && panel == nil { store.returnToSuggestionsIfIdle() }
            }
        }
        .onChange(of: store.authState.isLoggedIn) { _, connected in
            if !connected { panel = nil }
        }
        .onChange(of: store.pendingPlaylistRecommendation?.id) { _, id in
            if id != nil { panel = nil }
        }
        .task(id: panel) {
            while !Task.isCancelled {
                await store.refreshPlayback()
                do { try await Task.sleep(for: .seconds(panel == .lyrics ? 2 : 8)) }
                catch { return }
            }
        }
    }

    private var normalPlayer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header.padding(.horizontal, 20).padding(.vertical, 14)
                if !advanced && store.authState.isLoggedIn {
                    NowPlayingView(store: store, panel: panelBinding)
                        .padding(.horizontal, 20).padding(.bottom, 14)
                }
            }
            .fixedSize(horizontal: false, vertical: true).measurePanelSection("top")
            ScrollViewReader { scroller in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if advanced {
                            HStack {
                                Label(store.authState.displayText, systemImage: store.authState.isLoggedIn ? "checkmark.circle.fill" : "person.crop.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else if !store.authState.isLoggedIn {
                            AuthStatusView(store: store)
                        }
                        if advanced || panel == nil {
                            if hasRequestStatus { RequestStatusView(store: store) }
                            if let recommendation = store.pendingPlaylistRecommendation {
                                recommendationView(recommendation)
                            }
                        }
                        if advanced {
                            Divider()
                            DiagnosticsView(store: store)
                            DeveloperConsole(log: store.diagnostics, subscription: store.chatGPT)
                        } else if let panel, store.authState.isLoggedIn {
                            if store.showsRequestProgress || store.latestError != nil { RequestStatusView(store: store) }
                            if panel == .outputs {
                                SpotifyDevicePicker(store: store, details: store.playerDetails, close: { self.panel = nil })
                            } else {
                                PlayerDetailsView(store: store, details: store.playerDetails, settings: store.settings,
                                                  panel: panel, close: { self.panel = nil },
                                                  focusLyrics: { toggleLyricsFocus() })
                            }
                        } else if store.authState.isLoggedIn && store.requestState == .idle && store.pendingPlaylistRecommendation == nil {
                            suggestions
                        }
                    }
                    .id("panel-top")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .fixedSize(horizontal: false, vertical: true)
                    .measurePanelSection("body")
                }
                .scrollIndicators(.never)
                .frame(height: bodyHeight)
                .onChange(of: panel) { _, _ in scroller.scrollTo("panel-top", anchor: .top) }
                .onChange(of: advanced) { _, _ in scroller.scrollTo("panel-top", anchor: .top) }
            }
            VStack(spacing: 0) {
                PromptComposerView(store: store, beforeSubmit: { panel = nil })
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
                Divider().opacity(0.5)
                footer
            }
            .fixedSize(horizontal: false, vertical: true).measurePanelSection("bottom")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var advanced: Bool {
        get { presentation.advanced }
        nonmutating set { presentation.advanced = newValue }
    }
    private var panel: PlayerPanel? {
        get { presentation.panel }
        nonmutating set { presentation.selectPanel(newValue) }
    }
    private var panelBinding: Binding<PlayerPanel?> {
        Binding(get: { panel }, set: { panel = $0 })
    }
    private var focused: Bool { presentation.layout == .focusedLyrics }

    private func toggleLyricsFocus() {
        store.noteInteraction()
        rippleOrigin = wandPositions[focused ? "focused" : "normal"] ?? rippleOrigin
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.45)) {
            presentation.toggleLyricsFocus()
        }
    }

    private var lyricsTransition: AnyTransition {
        reduceMotion ? .opacity : .ripple(from: rippleOrigin)
    }

    private var focusedPlayer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SongIdentityView(store: store, compact: true)
                    .overlay {
                        if presentation.isDetached { SettingsDragRegion().accessibilityHidden(true) }
                    }
                LyricsModeButton(active: true, action: toggleLyricsFocus)
                    .measureWandPosition("focused")
                PlayerIconButton(title: presentation.isDetached ? "Return to menu bar" : "Open player window",
                                 symbol: presentation.isDetached ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                 action: toggleWindow)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            GeometryReader { geometry in
                PlayerDetailsView(store: store, details: store.playerDetails, settings: store.settings,
                                  panel: .lyrics, close: toggleLyricsFocus, focused: true,
                                  lyricsHeight: geometry.size.height)
                    .padding(.horizontal, 24)
            }
            .clipped()
            VStack(spacing: 10) {
                if store.latestError != nil { RequestStatusView(store: store) }
                PlaybackControlsView(store: store, panel: panelBinding, selectPanel: { panel = $0 })
            }
            .padding(.horizontal, 36).padding(.top, 14).padding(.bottom, 16)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity)
    }

    private var hasRequestStatus: Bool {
        store.showsRequestProgress || store.latestError != nil || store.latestResult != nil ||
            store.notificationNotice != nil || store.unfinishedPlaylist != nil
    }
    private var topHeight: CGFloat { measurements["top"] ?? 250 }
    private var bottomHeight: CGFloat { measurements["bottom"] ?? 92 }
    private var bodyHeight: CGFloat {
        if let height = presentation.windowHeight {
            return max(0, height - topHeight - bottomHeight)
        }
        return naturalBodyHeight
    }
    private var naturalBodyHeight: CGFloat {
        let readingPanel = !advanced && (panel == .lyrics || panel == .queue)
        return PanelSizing.bodyHeight(content: measurements["body"] ?? 120,
                                      top: topHeight, bottom: bottomHeight, maximum: min(maximumHeight, presentation.maximumHeight),
                                      readingPanel: readingPanel)
    }
    private var totalHeight: CGFloat { ceil(topHeight + naturalBodyHeight + bottomHeight) }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VibeCast").font(.system(size: 23, weight: .semibold, design: .rounded))
                if advanced { Text("DEVELOPER VIEW").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if presentation.isDetached { SettingsDragRegion().accessibilityHidden(true) }
            }
            PlayerIconButton(title: presentation.isDetached ? "Return to menu bar" : "Open player window",
                             symbol: presentation.isDetached ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             action: toggleWindow)
            PlayerIconButton(title: "Settings", symbol: "slider.horizontal.3", action: openSettings)
            PlayerIconButton(title: "Quit VibeCast", symbol: "power") { NSApp.terminate(nil) }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A little inspiration").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ForEach([("Late-night drive", "moon.stars", "late night driving"),
                     ("A little focus", "headphones", "find a focus playlist"),
                     ("Something with energy", "bolt", "play some EDM songs")], id: \.0) { title, icon, prompt in
                Button {
                    store.prompt = prompt
                    store.submitPrompt()
                } label: {
                    HStack {
                        Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
                        Text(title)
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
    }

    private func recommendationView(_ item: PendingPlaylistRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("FOUND FOR YOU", systemImage: "sparkle")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.teal)
                Spacer()
                Button { store.dismissRecommendation() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Dismiss recommendation").accessibilityLabel("Dismiss recommendation")
            }
            HStack(alignment: .top, spacing: 12) {
                CoverArtwork(url: item.playlist.artworkURL, size: 64, symbol: "music.note.list")
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.playlist.name).font(.system(size: 16, weight: .semibold)).lineLimit(3)
                    Text(item.playlist.ownerName ?? "Playlist on Spotify")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let url = item.playlist.spotifyURL {
                        Link("Open in Spotify", destination: url).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { store.acceptPlaylistRecommendation(id: item.id) } label: {
                    Label("Sure!", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .modifier(PrimaryMusicButton())
                Button { store.castMagic(from: item.id) } label: {
                    Label("Cast Magic", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.pink)
            }
            .controlSize(.large)
            .disabled(store.isBusy)
        }
        .padding(16)
        .modifier(RaisedPlayerSurface())
    }

    private var footer: some View {
        HStack {
            Circle().fill(store.authState.isLoggedIn ? Color.teal : Color.secondary.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(store.authState.isLoggedIn ? "Spotify connected" : "Spotify disconnected")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button { advanced.toggle() } label: {
                Image(systemName: advanced ? "music.note" : "terminal")
                Text(advanced ? "Player" : "Adv")
            }
            .accessibilityLabel(advanced ? "Switch to player view" : "Switch to developer view")
            .help("Switch view")
            .font(.system(size: 10))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

private struct DetachedPlayerSurface: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content
            .background {
                if enabled { RoundedRectangle(cornerRadius: 12).fill(.regularMaterial) }
            }
            .overlay {
                if enabled {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.16), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: enabled ? 12 : 0))
    }
}

struct PrimaryMusicButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct CoverArtwork: View {
    let url: URL?
    let size: CGFloat
    var symbol = "waveform"
    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                Image(systemName: symbol).font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.teal)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
