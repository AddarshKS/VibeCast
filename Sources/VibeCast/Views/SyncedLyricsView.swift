import SwiftUI

struct SyncedLyricsView: View {
    @ObservedObject var store: VibeCastStore
    let lyrics: TimedLyrics
    let trackURI: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var follow = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let position = store.playback?.elapsedMS(observedAt: store.playbackUpdatedAt, now: context.date) ?? 0
            let fresh = !store.playbackRefreshFailed && context.date.timeIntervalSince(store.playbackUpdatedAt) < 12
            let active = fresh ? lyrics.activeLine(at: position) : nil
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(lyrics.lines) { line in
                            Button {
                                guard let trackURI else { return }
                                follow = true
                                store.control(.seek(positionMS: line.timeMS, trackURI: trackURI))
                            } label: {
                                Text(line.text.isEmpty ? "\u{00B7} \u{00B7} \u{00B7}" : line.text)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(line.id == active ? Color.primary : Color.secondary.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                                .buttonStyle(.plain)
                                .disabled(store.isBusy || !fresh || !canSeek(line))
                                .help("Jump to \(line.timeMS / 60000):\(String(format: "%02d", (line.timeMS / 1000) % 60))")
                                .id(line.id)
                                .accessibilityAddTraits(line.id == active ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 85)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .modifier(LyricScrollTracking(follow: $follow))
                .overlay(alignment: .topTrailing) {
                    if !fresh {
                        Text("Reconnecting to Spotify").font(.caption).foregroundStyle(.secondary)
                            .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    PlayerIconButton(title: follow ? "Pause lyric following" : "Follow song",
                                     symbol: follow ? "location.fill" : "location", active: follow) {
                        follow.toggle()
                        if follow { scroll(proxy, to: active) }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)).padding(4)
                }
                .onChange(of: active, initial: true) { _, value in
                    if follow && fresh { scroll(proxy, to: value) }
                }
            }
        }
        .frame(height: 250)
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: Int?) {
        guard let id = id ?? lyrics.lines.first?.id else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
    }

    private func canSeek(_ line: LyricLine) -> Bool {
        guard let trackURI, store.playback?.item?.uri == trackURI,
              let duration = store.playback?.item?.durationMS else { return false }
        return !line.text.isEmpty && line.timeMS >= 0 && line.timeMS < duration &&
            store.playback?.actions?.disallows?["seeking"] != true && store.playback?.device?.isRestricted != true
    }
}

private struct LyricScrollTracking: ViewModifier {
    @Binding var follow: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { follow = false }
            }
        } else {
            // macOS 14 retains the explicit follow/pause control without scroll-phase APIs.
            content
        }
    }
}
