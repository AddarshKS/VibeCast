import Combine
import Foundation

@MainActor
final class PlayerPresentation: ObservableObject {
    enum Layout: Equatable { case standard, queue, lyrics, focusedLyrics }
    static let minimumHeight: CGFloat = 405

    @Published var isDetached = false
    @Published var maximumHeight: CGFloat = 680
    @Published var windowHeight: CGFloat?
    @Published var panel: PlayerPanel?
    @Published var advanced = false
    @Published private(set) var lyricsFocused = false
    private(set) var standardHeight: CGFloat?
    private(set) var focusedHeight: CGFloat?

    var layout: Layout {
        if advanced { return .standard }
        if panel == .queue { return .queue }
        if panel == .lyrics && lyricsFocused { return .focusedLyrics }
        if panel == .lyrics { return .lyrics }
        return .standard
    }

    var isHeightLocked: Bool { !isDetached || layout == .queue || layout == .lyrics }

    func selectPanel(_ panel: PlayerPanel?) {
        lyricsFocused = false
        self.panel = panel
    }

    func toggleLyricsFocus() {
        guard !advanced, panel == .lyrics else { return }
        lyricsFocused.toggle()
    }

    func resetWindowSize(preservingLyricsFocus: Bool = false) {
        standardHeight = nil
        focusedHeight = nil
        windowHeight = nil
        if !preservingLyricsFocus { lyricsFocused = false }
    }

    func recordResize(_ height: CGFloat) {
        guard height.isFinite, isDetached, !isHeightLocked else { return }
        let height = constrained(height)
        if layout == .focusedLyrics { focusedHeight = height }
        else { standardHeight = height }
        windowHeight = height
    }

    func desiredHeight(natural: CGFloat) -> CGFloat {
        let height: CGFloat
        switch layout {
        case .standard: height = standardHeight ?? natural
        case .queue, .lyrics: height = natural
        case .focusedLyrics: height = focusedHeight ?? windowHeight ?? natural
        }
        return constrained(height)
    }

    private func constrained(_ height: CGFloat) -> CGFloat {
        min(max(min(Self.minimumHeight, maximumHeight), height), maximumHeight)
    }
}
