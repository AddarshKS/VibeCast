import SwiftUI

struct WandPositions: PreferenceKey {
    static let defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func measureWandPosition(_ name: String) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("player"))
                Color.clear.preference(key: WandPositions.self, value: [name: CGPoint(x: frame.midX, y: frame.midY)])
            }
        }
    }
}

extension AnyTransition {
    static func ripple(from origin: CGPoint) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: RippleMask(progress: 0, origin: origin, erasing: false),
                                 identity: RippleMask(progress: 1, origin: origin, erasing: false)),
            removal: .modifier(active: RippleMask(progress: 1, origin: origin, erasing: true),
                               identity: RippleMask(progress: 0, origin: origin, erasing: true)))
    }
}

private struct RippleMask: ViewModifier, Animatable {
    nonisolated var progress: CGFloat
    let origin: CGPoint
    let erasing: Bool
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geometry in
                let radius = hypot(max(origin.x, geometry.size.width - origin.x),
                                   max(origin.y, geometry.size.height - origin.y)) + 2
                // Complementary masks reveal the new layout from the button in
                // either direction, regardless of which layout is above the other.
                RippleShape(origin: origin, radius: radius * min(1, max(0, progress)), erasing: erasing)
                    .fill(style: FillStyle(eoFill: true))
            }
        }
    }
}

private struct RippleShape: Shape {
    let origin: CGPoint
    let radius: CGFloat
    let erasing: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if erasing { path.addRect(rect) }
        path.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}
