import Combine
import Foundation

@MainActor
final class PlayerPresentation: ObservableObject {
    enum Layout: Equatable { case standard, queue, lyrics, miniplayer }
    static let density = PlayerDensity.compact
    static let width = density.width
    static let minimumHeight: CGFloat = 344
    static let readingHeight: CGFloat = 544

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
    @Published private(set) var miniplayer = false
    @Published private(set) var miniplayerPanel: PlayerPanel?
    private(set) var miniplayerDetailHeight: CGFloat = width
    private(set) var miniplayerQueueActivation = 0
    private(set) var readingHeights: [PlayerPanel: CGFloat] = [:]

    var layout: Layout {
        if advanced { return .standard }
        if miniplayer { return .miniplayer }
        if panel == .queue { return .queue }
        if panel == .lyrics { return .lyrics }
        return .standard
    }

    var isReading: Bool { layout == .lyrics || layout == .queue }
    var isHeightLocked: Bool { !isDetached || !isReading }
    var showsComposer: Bool { advanced || (panel == nil && !miniplayer) }

    func selectPanel(_ panel: PlayerPanel?) {
        miniplayerPanel = nil
        miniplayer = false
        self.panel = panel
    }

    func toggleMiniplayer() {
        advanced = false
        miniplayerPanel = nil
        panel = nil
        miniplayer.toggle()
    }

    func toggleMiniplayerPanel(_ panel: PlayerPanel) {
        guard miniplayer, !advanced, panel == .lyrics || panel == .queue else { return }
        if miniplayerPanel == nil { miniplayerDetailHeight = windowHeight ?? Self.width }
        miniplayerPanel = miniplayerPanel == panel ? nil : panel
        if miniplayerPanel == .queue { miniplayerQueueActivation += 1 }
    }

    func toggleAdvanced() {
        selectPanel(nil)
        advanced.toggle()
    }

    func resetWindowSize() {
        readingHeights.removeAll()
        windowHeight = nil
    }

    func recordResize(_ height: CGFloat) {
        guard height.isFinite, isDetached, !isHeightLocked, let panel else { return }
        let height = constrained(height)
        readingHeights[panel] = height
        windowHeight = height
    }

    func desiredHeight(natural: CGFloat) -> CGFloat {
        let height: CGFloat
        switch layout {
        case .standard, .miniplayer: height = natural
        case .queue, .lyrics: height = isDetached ? (panel.flatMap { readingHeights[$0] } ?? natural) : natural
        }
        return isReading ? constrained(height) : min(max(1, height), maximumHeight)
    }

    private func constrained(_ height: CGFloat) -> CGFloat {
        min(max(min(Self.minimumHeight, maximumHeight), height), maximumHeight)
    }
}
