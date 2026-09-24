import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: VibeCastStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Version", value: AppConfig.version)
            LabeledContent("Route", value: store.lastRouteName ?? "Ready")
            LabeledContent("Spotify action", value: DiagnosticLog.redacted(store.lastSpotifyAction ?? "-"))
            LabeledContent("State", value: store.isBusy ? "In progress" : (store.lastRequestOutcome ?? store.requestState.displayText))
            if let stage = store.lastRequestStage {
                LabeledContent("Stage", value: DiagnosticLog.redacted(stage))
            }
            if let prompt = store.lastRequestPrompt {
                LabeledContent("Original prompt", value: DiagnosticLog.redacted(prompt))
            }
            if let resolved = store.lastResolvedItem {
                LabeledContent("Resolved", value: DiagnosticLog.redacted(resolved))
            }
            if let recommendation = store.pendingPlaylistRecommendation {
                LabeledContent("Search", value: DiagnosticLog.redacted(recommendation.searchPhrase))
                LabeledContent("Pending", value: DiagnosticLog.redacted(recommendation.playlist.name))
                if recommendation.originalPrompt != store.lastRequestPrompt {
                    LabeledContent("Recommendation prompt", value: DiagnosticLog.redacted(recommendation.originalPrompt))
                }
            }
            Text("RECENT REQUESTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if store.requestHistory.isEmpty { Text("No requests yet.").foregroundStyle(.secondary) }
            ForEach(store.requestHistory) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Label(DiagnosticLog.redacted(item.message), systemImage: item.status.symbol)
                        .foregroundStyle(item.status == .failure ? Color.orange : Color.primary)
                    Text(DiagnosticLog.redacted("\(item.routeName) - \(item.prompt)")).foregroundStyle(.secondary)
                    if let stage = item.stage {
                        Text("Stage: \(DiagnosticLog.redacted(stage))").foregroundStyle(.secondary)
                    }
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
