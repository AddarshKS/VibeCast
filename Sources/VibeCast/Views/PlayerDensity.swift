import SwiftUI

// Shared player metrics. The regular preset is retained for baseline comparisons.
enum PlayerDensity: Hashable {
    case regular, compact

    func value(_ regular: CGFloat, _ compact: CGFloat) -> CGFloat {
        self == .compact ? compact : regular
    }

    var width: CGFloat { value(400, 340) }
    var inset: CGFloat { value(20, 14) }
    var buttonSize: CGFloat { value(30, 28) }
    var detailSpacing: CGFloat { value(14, 10) }
    var bodyBottom: CGFloat { value(12, 8) }
    var readingHeight: CGFloat { value(320, 250) }
    var lyricsReserve: CGFloat { buttonSize + detailSpacing + bodyBottom }
    var lyricsFont: CGFloat { value(22, 18) }
}

private struct PlayerDensityKey: EnvironmentKey {
    static let defaultValue = PlayerDensity.regular
}

extension EnvironmentValues {
    var playerDensity: PlayerDensity {
        get { self[PlayerDensityKey.self] }
        set { self[PlayerDensityKey.self] = newValue }
    }
}
