import SwiftUI

/// Instantiated only while hovered, so idle controls do not run an animation clock.
struct ControlHoverGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var cornerRadius: CGFloat = 8
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(started))
            let phase = reduceMotion ? 0.5 : elapsed.truncatingRemainder(dividingBy: 2.2) / 2.2
            let shape = RoundedRectangle(cornerRadius: cornerRadius)
            let center = -0.45 + phase * 1.9
            let wave = LinearGradient(colors: [.clear, .teal.opacity(0.85), .white.opacity(0.85), .teal.opacity(0.85), .clear],
                                      startPoint: UnitPoint(x: center - 0.3, y: 0.5),
                                      endPoint: UnitPoint(x: center + 0.3, y: 0.5))
            ZStack {
                shape.fill(.teal.opacity(0.07))
                shape.fill(wave).opacity(0.13)
                shape.strokeBorder(.teal.opacity(0.35), lineWidth: 1)
                    .shadow(color: .teal.opacity(0.25), radius: 5)
                shape.strokeBorder(wave, lineWidth: 1.5)
                    .shadow(color: .teal.opacity(0.5), radius: 4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
