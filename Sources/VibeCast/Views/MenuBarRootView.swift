import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: VibeCastStore
    @ObservedObject var presentation: PlayerPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rippleOrigins: [String: CGPoint] = [:]
    @State private var rippleOrigin = CGPoint(x: 100, y: 300)
    @State private var measurements: [String: CGFloat] = [:]
    var maximumHeight: CGFloat = 680
    var resize: (CGFloat) -> Void = { _ in }
    var toggleWindow: () -> Void = {}

    init(store: VibeCastStore, developerView: Bool = false, panel: PlayerPanel? = nil,
         maximumHeight: CGFloat = 680, resize: @escaping (CGFloat) -> Void = { _ in },
         presentation: PlayerPresentation = PlayerPresentation(),
         toggleWindow: @escaping () -> Void = {}) {
        self.store = store
        self.presentation = presentation
        self.toggleWindow = toggleWindow
        if developerView { presentation.advanced = true }
        if let panel { presentation.panel = panel }
        self.maximumHeight = maximumHeight
        self.resize = resize
    }

    var body: some View {
        ZStack(alignment: .top) {
            if mini {
                ScrollView {
                    MiniplayerView(store: store, presentation: presentation,
                                   toggleMiniplayer: toggleMiniplayer, toggleWindow: toggleWindow,
                                   toggleDetail: toggleMiniplayerPanel, detailTransition: readingTransition,
                                   selectPanel: selectPanel)
                        .fixedSize(horizontal: false, vertical: true)
                        .measurePanelSection("mini")
                }
                .scrollIndicators(.never)
                .frame(height: presentation.windowHeight ?? totalHeight)
                .transition(readingTransition).zIndex(2)
            } else if presentation.isReading, let panel {
                ReadingPlayerView(store: store, presentation: presentation, panel: panel,
                                  toggleMiniplayer: toggleMiniplayer, toggleWindow: toggleWindow,
                                  selectPanel: selectPanel)
                    .id(panel).transition(readingTransition).zIndex(1)
            } else {
                normalPlayer.transition(readingTransition).zIndex(0)
            }
        }
        // AppKit owns the outer height. Pin content to its top even during the
        // frame between a SwiftUI state change and the native popover resize.
        .frame(width: density.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "player")
        .modifier(DetachedPlayerSurface(enabled: presentation.isDetached))
        .tint(.teal)
        .environment(\.playerDensity, density)
        .onPreferenceChange(RippleOrigins.self) { value in
            rippleOrigins.merge(value, uniquingKeysWith: { _, latest in latest })
        }
        .onPreferenceChange(PanelMeasurements.self) { value in
            if let height = value["mini"], measurements["mini"] != height { measurements["mini"] = height }
            if !presentation.isReading && !mini && !value.isEmpty {
                let next = measurements.merging(value, uniquingKeysWith: { _, latest in latest })
                if next != measurements { measurements = next }
            }
        }
        .onChange(of: totalHeight, initial: true) { _, height in resize(height) }
        // Equal-height modes still need their native resize policy and saved size applied.
        .onChange(of: presentation.layout) { _, _ in resize(totalHeight) }
        .onChange(of: store.prompt) { _, _ in store.noteInteraction() }
        .onChange(of: panel) { _, _ in store.noteInteraction() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if !advanced && !mini && panel == nil { store.returnToSuggestionsIfIdle() }
            }
        }
        .onChange(of: store.authState.isLoggedIn) { _, connected in
            if !connected { panel = nil }
        }
        .onChange(of: store.pendingPlaylistRecommendation?.id) { _, id in
            if id != nil { panel = nil }
        }
        .task(id: "\(panel?.rawValue ?? "player")|\(presentation.miniplayerPanel?.rawValue ?? "player")") {
            while !Task.isCancelled {
                await store.refreshPlayback()
                let interval = panel == .lyrics || panel == .queue || presentation.miniplayerPanel != nil ? 2 : 8
                do { try await Task.sleep(for: .seconds(interval)) }
                catch { return }
            }
        }
    }

    private var normalPlayer: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header.padding(.horizontal, density.inset).padding(.vertical, density.value(14, 10))
                if !advanced && store.authState.isLoggedIn {
                    NowPlayingView(store: store, panel: panelBinding, detached: presentation.isDetached,
                                   toggleWindow: toggleWindow, toggleMiniplayer: toggleMiniplayer)
                        .padding(.horizontal, density.inset).padding(.bottom, density.value(14, 10))
                }
            }
            .fixedSize(horizontal: false, vertical: true).measurePanelSection("top")
            ScrollViewReader { scroller in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: density.value(16, 12)) {
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
                        } else if panel == .outputs, store.authState.isLoggedIn {
                            if store.showsRequestProgress || store.latestError != nil {
                                RequestStatusView(store: store).measurePanelSection("detail-status")
                            }
                            SpotifyDevicePicker(store: store, details: store.playerDetails, close: { self.panel = nil })
                        } else if store.authState.isLoggedIn && store.requestState == .idle && store.pendingPlaylistRecommendation == nil {
                            suggestions
                        }
                    }
                    .id("panel-top")
                    .transition(.opacity)
                    .id(panel)
                    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.2), value: panel)
                    .padding(.horizontal, density.inset)
                    .padding(.bottom, density.bodyBottom)
                    .fixedSize(horizontal: false, vertical: true)
                    .measurePanelSection(bodyMeasurementKey)
                }
                .scrollIndicators(.never)
                .frame(height: bodyHeight)
                .animation(nil, value: bodyHeight)
                .onChange(of: panel) { _, _ in
                    scroller.scrollTo("panel-top", anchor: .top)
                }
                .onChange(of: advanced) { _, _ in scroller.scrollTo("panel-top", anchor: .top) }
            }
            VStack(spacing: 0) {
                if presentation.showsComposer {
                    PromptComposerView(store: store, beforeSubmit: { panel = nil })
                        .padding(.horizontal, density.inset)
                        .padding(.top, density.value(8, 6)).padding(.bottom, density.value(20, 16))
                }
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
        nonmutating set { selectPanel(newValue) }
    }
    private var panelBinding: Binding<PlayerPanel?> {
        Binding(get: { panel }, set: { panel = $0 })
    }
    private var mini: Bool { presentation.layout == .miniplayer }
    private var density: PlayerDensity { PlayerPresentation.density }
    private var bodyMeasurementKey: String { "body-\(advanced ? "advanced" : panel?.rawValue ?? "landing")" }

    private func selectPanel(_ value: PlayerPanel?) {
        store.noteInteraction()
        let readingChange = presentation.isReading || value == .lyrics || value == .queue
        let originPanel = value ?? panel
        if let originPanel { rippleOrigin = rippleOrigins["mini-\(originPanel.rawValue)-enter"] ?? rippleOrigin }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : (readingChange ? 0.45 : 0.2))) {
            presentation.selectPanel(value)
        }
    }

    private func toggleMiniplayer() {
        store.noteInteraction()
        rippleOrigin = rippleOrigins[mini ? "mini-album" : "album"] ?? rippleOrigin
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.45)) {
            presentation.toggleMiniplayer()
        }
    }

    private func toggleMiniplayerPanel(_ panel: PlayerPanel) {
        store.noteInteraction()
        let direction = presentation.miniplayerPanel == panel ? "exit" : "enter"
        rippleOrigin = rippleOrigins["mini-\(panel.rawValue)-\(direction)"]
            ?? CGPoint(x: density.width / 2, y: density.width / 2)
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.45)) {
            presentation.toggleMiniplayerPanel(panel)
        }
    }

    private var readingTransition: AnyTransition {
        reduceMotion ? .opacity : .ripple(from: rippleOrigin)
    }

    private var hasRequestStatus: Bool {
        store.showsRequestProgress || store.latestError != nil || store.latestResult != nil ||
            store.notificationNotice != nil || store.unfinishedPlaylist != nil
    }
    private var topHeight: CGFloat { measurements["top"] ?? density.value(250, 220) }
    private var bottomHeight: CGFloat { presentation.showsComposer ? (measurements["bottom"].flatMap { $0 > 0 ? $0 : nil } ?? 60) : 0 }
    private var bodyHeight: CGFloat {
        if let height = presentation.windowHeight {
            return max(0, height - topHeight - bottomHeight)
        }
        return naturalBodyHeight
    }
    private var naturalBodyHeight: CGFloat {
        return PanelSizing.bodyHeight(content: max(!advanced && panel == nil ? 114 : 0, measurements[bodyMeasurementKey] ?? 120),
                                      top: topHeight, bottom: bottomHeight, maximum: min(maximumHeight, presentation.maximumHeight))
    }
    private var totalHeight: CGFloat {
        if mini { return min(ceil(measurements["mini"] ?? PlayerPresentation.width), presentation.maximumHeight) }
        if presentation.isReading { return min(PlayerPresentation.readingHeight, presentation.maximumHeight) }
        return ceil(topHeight + naturalBodyHeight + bottomHeight)
    }

    private var header: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 2) {
                Text("VibeCast").font(.system(size: density.value(23, 20), weight: .semibold, design: .rounded))
                if advanced { Text("DEVELOPER VIEW").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity)
            .overlay {
                if presentation.isDetached { SettingsDragRegion().accessibilityHidden(true) }
            }
            if advanced || !store.authState.isLoggedIn {
                PlayerWindowButton(detached: presentation.isDetached, action: toggleWindow)
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: density.value(10, 6)) {
            Text("A little inspiration").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ForEach([("Long Drive Night", "moon.stars", "late night driving"),
                     ("Need to Focus", "headphones", "find a focus playlist"),
                     ("Play Something Energetic", "bolt", "play some EDM songs")], id: \.0) { title, icon, prompt in
                Button {
                    store.prompt = prompt
                    store.submitPrompt()
                } label: {
                    HStack {
                        Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
                        Text(title)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, density.value(5, 4))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
    }

    private func recommendationView(_ item: PendingPlaylistRecommendation) -> some View {
        VStack(alignment: .leading, spacing: density.value(14, 10)) {
            HStack {
                Label("FOUND FOR YOU", systemImage: "sparkle")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.teal)
                Spacer()
                Button { store.dismissRecommendation() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Dismiss recommendation").accessibilityLabel("Dismiss recommendation")
            }
            HStack(alignment: .top, spacing: 12) {
                CoverArtwork(url: item.playlist.artworkURL, size: density.value(64, 48), symbol: "music.note.list")
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.playlist.name).font(.system(size: density.value(16, 14), weight: .semibold)).lineLimit(3)
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
            .controlSize(density == .compact ? .regular : .large)
            .disabled(store.isBusy)
        }
        .padding(density.value(16, 12))
        .modifier(RaisedPlayerSurface())
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
        PlayerArtwork(url: url) { image in
            if let image {
                image.resizable().scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    Image(systemName: symbol).font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.teal)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
