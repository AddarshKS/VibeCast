import AppKit
import SwiftUI
import Testing
@testable import VibeCast

@MainActor
@Suite(.serialized)
struct RippleTests {
    @Test func completedClipTracksResizedBoundsInBothDirections() {
        for height in [344.0, 544, 760, 1000] {
            let rect = CGRect(x: 0, y: 0, width: 340, height: height)
            for erasing in [false, true] {
                let visible = RippleShape(progress: erasing ? 0 : 1, origin: CGPoint(x: 310, y: 40), erasing: erasing)
                #expect(visible.path(in: rect).boundingRect == rect)
                let hidden = RippleShape(progress: erasing ? 1 : 0, origin: .zero, erasing: erasing)
                #expect(hidden.path(in: rect).isEmpty)
            }
        }
    }

    @Test func rippleInsertionAndRemovalAreComplementary() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 500)
        for progress in [0.05, 0.25, 0.5, 0.75, 0.95] {
            let inserted = RippleShape(progress: progress, origin: CGPoint(x: 290, y: 30), erasing: false).path(in: rect)
            let removed = RippleShape(progress: progress, origin: CGPoint(x: 290, y: 30), erasing: true).path(in: rect)
            for x in stride(from: 1.0, to: 340, by: 17) {
                for y in stride(from: 1.0, to: 500, by: 17) {
                    let point = CGPoint(x: x, y: y)
                    // Path containment includes the antialiased circle boundary
                    // in both paths; compare their interiors, not that shared edge.
                    if abs(hypot(x - 290, y - 30) - inserted.boundingRect.width / 2) < 1 { continue }
                    #expect(inserted.contains(point, eoFill: true) != removed.contains(point, eoFill: true))
                }
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VIBECAST_RENDER_UI"] == "1"))
    func rippleDoesNotRecreateContentAtEitherEndpoint() async throws {
        _ = NSApplication.shared
        let state = RippleTestState()
        let lifetime = RippleLifetime()
        let host = NSHostingView(rootView: RippleTestView(state: state, lifetime: lifetime))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 340),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        try await Task.sleep(for: .milliseconds(50))
        for cycle in 1...3 {
            withAnimation(.easeInOut(duration: 0.2)) { state.show = true }
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(16))
                host.layoutSubtreeIfNeeded()
            }
            #expect(lifetime.created == cycle, "Revealing content must create it once, not again when the ripple completes.")
            withAnimation(.easeInOut(duration: 0.2)) { state.show = false }
            for _ in 0..<20 {
                try await Task.sleep(for: .milliseconds(16))
                host.layoutSubtreeIfNeeded()
            }
            #expect(lifetime.created == cycle, "Erasing content must not rebuild it at the start of removal.")
        }
    }
}

@MainActor private final class RippleTestState: ObservableObject {
    @Published var show = false
}

@MainActor private final class RippleLifetime {
    var created = 0
}

private struct RippleTestView: View {
    @ObservedObject var state: RippleTestState
    let lifetime: RippleLifetime
    var body: some View {
        ZStack {
            Color.black
            if state.show {
                RippleLifetimeProbe(lifetime: lifetime)
                    .transition(.ripple(from: CGPoint(x: 170, y: 50)))
            }
        }
    }
}

private struct RippleLifetimeProbe: NSViewRepresentable {
    let lifetime: RippleLifetime
    func makeNSView(context: Context) -> NSView {
        lifetime.created += 1
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemTeal.cgColor
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
