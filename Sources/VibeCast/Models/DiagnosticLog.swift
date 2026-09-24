import Foundation

@MainActor
final class DiagnosticLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let area: String
        let message: String
        let isError: Bool
    }
    @Published private(set) var entries: [Entry] = []

    func record(_ area: String, _ message: String, isError: Bool = false) {
        entries.insert(Entry(area: Self.redacted(area), message: Self.redacted(message), isError: isError), at: 0)
        entries = Array(entries.prefix(100))
    }

    func clear() { entries = [] }
    var text: String {
        entries.reversed().map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.area)] \($0.isError ? "ERROR: " : "")\($0.message)" }
            .joined(separator: "\n")
    }

    // Sanitize at ingestion so on-screen and copied diagnostics have the same
    // privacy boundary, even when a provider includes credentials in an error.
    nonisolated static func redacted(_ text: String) -> String {
        let credential = #"(?:access[_-]?token|refresh[_-]?token|id[_-]?token|api[_-]?key|client[_-]?secret|code[_-]?verifier|authorization|password|cookie|set-cookie|token)"#
        let rules: [(String, String)] = [
            (#"(?i)(\b(?:bearer|basic)\s+)[A-Za-z0-9._~+/=-]+"#, "$1[redacted]"),
            (#"(?i)([\"']?"# + credential + #"[\"']?\s*[:=]\s*\")[^\"]*(\")"#, "$1[redacted]$2"),
            (#"(?i)([\"']?"# + credential + #"[\"']?\s*[:=]\s*')[^']*(')"#, "$1[redacted]$2"),
            (#"(?i)([\"']?"# + credential + #"[\"']?\s*[:=]\s*\")[^\"]*$"#, "$1[redacted]"),
            (#"(?i)([\"']?"# + credential + #"[\"']?\s*[:=]\s*')[^']*$"#, "$1[redacted]"),
            (#"(?i)([\"']?"# + credential + #"[\"']?\s*[:=]\s*)(?:\[redacted\]|(?![\"'])[^,\s;&}\]]+)"#, "$1[redacted]"),
            (#"(?i)([?&](?:code|state|key|signature|code_challenge)=)[^&#\s]+"#, "$1[redacted]"),
            (#"\bsk-[A-Za-z0-9_-]{8,}\b"#, "[redacted]"),
            (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "[redacted]"),
            (#"(?i)(https?://)[^/\s:@]+:[^/\s@]+@"#, "$1[redacted]@"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[redacted-email]"),
            (#"/Users/[^/\s]+"#, "/Users/[redacted]")
        ]
        let sanitized = rules.reduce(text) { value, rule in
            value.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }
        return sanitized.count > 4_096 ? String(sanitized.prefix(4_096)) + "… [truncated]" : sanitized
    }
}
