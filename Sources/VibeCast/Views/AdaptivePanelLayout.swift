import SwiftUI

enum PanelSizing {
    static func bodyHeight(content: CGFloat, top: CGFloat, bottom: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(0, content), max(0, maximum - top - bottom))
    }
}

struct PanelMeasurements: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func measurePanelSection(_ name: String) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelMeasurements.self, value: [name: geometry.size.height])
            }
        }
    }
}
