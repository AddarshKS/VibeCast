import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: VibeCastStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.lastRouteName != nil || store.lastSpotifyAction != nil || store.lastResolvedItem != nil {
                VStack(alignment: .leading, spacing: 4) {
                    diagnosticRow("Route", store.lastRouteName)
                    diagnosticRow("Spotify action", store.lastSpotifyAction)
                    diagnosticRow("Resolved", store.lastResolvedItem)
                }
            }

            if !store.requestHistory.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(store.requestHistory) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: item.status == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(item.status == .success ? .green : .red)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.message)
                                    .lineLimit(1)
                                Text("\(item.routeName) - \(item.prompt)")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func diagnosticRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)

            Text(value ?? "-")
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}
