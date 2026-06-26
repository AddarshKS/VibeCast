import SwiftUI

struct RouteReadinessView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readinessRow("Spotify API", systemImage: "checkmark.circle.fill", color: .green, note: "pause, resume, skip, repeat, shuffle, track search")
            readinessRow("Codex interpreter", systemImage: "hammer.circle", color: .orange, note: "stubbed for incomplete music requests")
            readinessRow("Codex chat", systemImage: "message.circle", color: .blue, note: "starter personality response")
            readinessRow("Computer fallback", systemImage: "desktopcomputer", color: .purple, note: "stubbed for mood and playlist requests")
        }
        .font(.caption)
    }

    private func readinessRow(_ title: String, systemImage: String, color: Color, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(title)
                .fontWeight(.semibold)
            Text(note)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
