import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: VibeCastStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Version", value: AppConfig.version)
            LabeledContent("Route", value: store.lastRouteName ?? "Ready")
            LabeledContent("Spotify action", value: store.lastSpotifyAction ?? "-")
            LabeledContent("State", value: store.isBusy ? store.progress : (store.latestError == nil ? "Ready" : "Failed"))
            if let resolved = store.lastResolvedItem {
                LabeledContent("Resolved", value: resolved)
            }
            if let recommendation = store.pendingPlaylistRecommendation {
                LabeledContent("Search", value: recommendation.searchPhrase)
                LabeledContent("Pending", value: recommendation.playlist.name)
                LabeledContent("Original prompt", value: recommendation.originalPrompt)
            }
            Text("RECENT REQUESTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if store.requestHistory.isEmpty { Text("No requests yet.").foregroundStyle(.secondary) }
            ForEach(store.requestHistory) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Label(item.message, systemImage: item.status == .success ? "checkmark" : "exclamationmark.circle")
                        .foregroundStyle(item.status == .success ? Color.primary : Color.orange)
                    Text("\(item.routeName) - \(item.prompt)").foregroundStyle(.secondary)
                    Text(item.createdAt.formatted(date: .omitted, time: .standard)).foregroundStyle(.tertiary)
                }
            }
            if !store.isBusy {
                Button("Clear current result") { store.clear() }.buttonStyle(.borderless)
            }
        }
        .font(.system(size: 11))
        .textSelection(.enabled)
    }
}
