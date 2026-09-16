import Combine
import Foundation

@MainActor
final class PlayerPresentation: ObservableObject {
    enum Layout: Equatable { case standard, queue, lyrics, focusedLyrics, miniplayer }
    static let density = PlayerDensity.compact
    static let width = density.width
    static let minimumHeight: CGFloat = 344

    @Published var isDetached = false
    @Published var maximumHeight: CGFloat = 680
    @Published var windowHeight: CGFloat?
    @Published var panel: PlayerPanel? {
        didSet {
            if panel == .queue, oldValue != .queue { queueActivation += 1 }
        }
    }
    private(set) var queueActivation = 0
    @Published var advanced = false
    @Published private(set) var lyricsFocused = false
    @Published private(set) var miniplayer = false
    private(set) var focusedHeight: CGFloat?

    var layout: Layout {
        if advanced { return .standard }
        if miniplayer { return .miniplayer }
        if panel == .queue { return .queue }
        if panel == .lyrics && lyricsFocused { return .focusedLyrics }
        if panel == .lyrics { return .lyrics }
        return .standard
    }

    var isHeightLocked: Bool { !isDetached || layout != .focusedLyrics }
    var showsComposer: Bool { advanced || (panel == nil && !miniplayer) }

    func selectPanel(_ panel: PlayerPanel?) {
        lyricsFocused = false
        miniplayer = false
        self.panel = panel
    }

    func toggleMiniplayer() {
        advanced = false
        lyricsFocused = false
        panel = nil
        miniplayer.toggle()
    }

    func toggleAdvanced() {
        selectPanel(nil)
        advanced.toggle()
    }

    func toggleLyricsFocus() {
        guard !advanced, panel == .lyrics else { return }
        lyricsFocused.toggle()
    }

    func resetWindowSize() {
        focusedHeight = nil
        windowHeight = nil
    }

    func recordResize(_ height: CGFloat) {
        guard height.isFinite, isDetached, !isHeightLocked else { return }
        let height = constrained(height)
        focusedHeight = height
        windowHeight = height
    }

    func desiredHeight(natural: CGFloat) -> CGFloat {
        let height: CGFloat
        switch layout {
        case .standard, .queue, .lyrics, .miniplayer: height = natural
        case .focusedLyrics: height = focusedHeight ?? windowHeight ?? natural
        }
        return layout == .focusedLyrics ? constrained(height) : min(max(1, height), maximumHeight)
    }

    private func constrained(_ height: CGFloat) -> CGFloat {
        min(max(min(Self.minimumHeight, maximumHeight), height), maximumHeight)
    }
}
