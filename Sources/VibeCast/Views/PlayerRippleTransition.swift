import SwiftUI

struct RippleOrigins: PreferenceKey {
    static let defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func measureRippleOrigin(_ name: String) -> some View {
        background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("player"))
                Color.clear.preference(key: RippleOrigins.self, value: [name: CGPoint(x: frame.midX, y: frame.midY)])
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
        // Keep the live screen's identity through both endpoints. Switching between
        // masked and unmasked content recreates artwork, scroll views and controls.
        content.clipShape(RippleShape(progress: progress, origin: origin, erasing: erasing),
                          style: FillStyle(eoFill: true))
    }
}

struct RippleShape: Shape {
    var progress: CGFloat
    let origin: CGPoint
    let erasing: Bool
    func path(in rect: CGRect) -> Path {
        // Derive clipping from the current bounds, including after a completed
        // transition is resized. No offscreen mask retains the original height.
        if erasing ? progress <= 0 : progress >= 1 { return Path(rect) }
        if erasing ? progress >= 1 : progress <= 0 { return Path() }
        let radius = (hypot(max(abs(origin.x - rect.minX), abs(rect.maxX - origin.x)),
                            max(abs(origin.y - rect.minY), abs(rect.maxY - origin.y))) + 2) * progress
        var path = Path()
        if erasing { path.addRect(rect) }
        path.addEllipse(in: CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2))
        return path
    }
}
