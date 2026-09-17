import SwiftUI

struct DeveloperConsole: View {
    @ObservedObject var log: DiagnosticLog
    @ObservedObject var subscription: ChatGPTSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            LabeledContent("ChatGPT", value: subscription.account == nil ? "Disconnected" : "Connected")
            if let error = subscription.error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Text("ACTIVITY LOG").fontWeight(.semibold)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.text, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .help("Copy activity log").accessibilityLabel("Copy activity log")
                Button { log.clear() } label: { Image(systemName: "trash") }
                    .help("Clear activity log").accessibilityLabel("Clear activity log")
            }
            .buttonStyle(.borderless)
            if log.entries.isEmpty { Text("No activity yet.").foregroundStyle(.secondary) }
            ForEach(log.entries) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.area)")
                        .foregroundStyle(.secondary)
                    Text(entry.message).foregroundStyle(entry.isError ? Color.orange : Color.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }
}
