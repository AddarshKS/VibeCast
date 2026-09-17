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
        entries.insert(Entry(area: area, message: message, isError: isError), at: 0)
        entries = Array(entries.prefix(100))
    }

    func clear() { entries = [] }
    var text: String {
        entries.reversed().map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.area)] \($0.isError ? "ERROR: " : "")\($0.message)" }
            .joined(separator: "\n")
    }
}
