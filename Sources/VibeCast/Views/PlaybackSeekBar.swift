import SwiftUI

struct PlaybackSeekBar: View {
    @ObservedObject var store: VibeCastStore
    @State private var scrub: PlaybackScrub?
    @State private var cancelled = false
    @State private var hovered = false
    @FocusState private var focused: Bool

    private var duration: Int { store.playback?.item?.durationMS ?? 0 }
    private var canSeek: Bool {
        !store.isBusy && !store.playbackRefreshFailed && duration > 0 &&
            store.playback?.item?.uri != nil && store.playback?.device?.id?.isEmpty == false &&
            store.playback?.device?.isRestricted != true && store.playback?.actions?.disallows?["seeking"] != true
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = displayedPosition(at: context.date)
            VStack(spacing: 5) {
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let fraction = min(1, max(0, Double(elapsed) / Double(max(1, duration))))
                    let highlighted = canSeek && (hovered || focused || scrub != nil)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.1)).frame(height: 3)
                        Capsule().fill(highlighted ? Color.teal : Color.primary.opacity(0.55))
                            .frame(width: width * fraction, height: 3)
                            .shadow(color: .teal.opacity(highlighted ? 0.6 : 0), radius: 4)
                        Circle().fill(.teal).frame(width: 8, height: 8)
                            .offset(x: max(0, min(width - 8, width * fraction - 4)))
                            .opacity(highlighted ? 1 : 0)
                    }
                    .frame(width: width, height: 16)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard canSeek, !cancelled else { cancelled = true; return }
                            if scrub == nil, let uri = store.playback?.item?.uri {
                                scrub = PlaybackScrub(trackURI: uri, durationMS: duration, positionMS: elapsed)
                            }
                            if let snapshot = scrub,
                               let position = PlaybackScrub.position(x: value.location.x, width: width, durationMS: snapshot.durationMS) {
                                scrub?.positionMS = position
                            }
                        }
                        .onEnded { value in
                            defer { scrub = nil; cancelled = false }
                            guard !cancelled, var snapshot = scrub,
                                  let position = PlaybackScrub.position(x: value.location.x, width: width, durationMS: snapshot.durationMS) else { return }
                            snapshot.positionMS = position
                            if let action = snapshot.action(currentURI: store.playback?.item?.uri, canSeek: canSeek) {
                                store.control(action)
                            }
                        })
                    .onHover { hovered = $0 }
                }
                .frame(height: 16)
                .focusable(canSeek)
                // The track glow already indicates focus; avoid a second rectangular focus ring.
                .focusEffectDisabled()
                .focused($focused)
                .onMoveCommand { direction in
                    if direction == .left { adjust(by: -5000) }
                    if direction == .right { adjust(by: 5000) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Song position")
                .accessibilityValue("\(time(elapsed)) of \(time(duration))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjust(by: 5000)
                    case .decrement: adjust(by: -5000)
                    @unknown default: break
                    }
                }
                .help("Seek in the current song")
                HStack {
                    Text(time(elapsed))
                    Spacer()
                    Text(time(duration))
                }
                .font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: store.playback?.item?.uri) { _, _ in if scrub != nil { cancelled = true } }
        .onChange(of: store.isBusy) { _, busy in if busy && scrub != nil { cancelled = true } }
        .onDisappear { scrub = nil; cancelled = false }
    }

    private func displayedPosition(at date: Date) -> Int {
        if let scrub, !cancelled, scrub.trackURI == store.playback?.item?.uri { return scrub.positionMS }
        if case .seek(let position, let uri) = store.pendingPlayerAction, uri == store.playback?.item?.uri { return position }
        return store.playback?.elapsedMS(observedAt: store.playbackUpdatedAt, now: date) ?? 0
    }

    private func adjust(by delta: Int) {
        guard canSeek, let uri = store.playback?.item?.uri else { return }
        let position = min(duration - 1, max(0, displayedPosition(at: Date()) + delta))
        store.control(.seek(positionMS: position, trackURI: uri))
    }

    private func time(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
