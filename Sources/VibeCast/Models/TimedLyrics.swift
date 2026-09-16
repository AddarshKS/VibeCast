import Foundation

struct LyricLine: Equatable, Sendable, Identifiable {
    let timeMS: Int
    let text: String
    var id: Int { timeMS }
}

struct TimedLyrics: Equatable, Sendable {
    let lines: [LyricLine]

    init?(lrc: String) {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let source = lrc as NSString
        var offset = 0
        if let match = offsetPattern.firstMatch(in: lrc, range: NSRange(location: 0, length: source.length)) {
            if let parsed = Int(source.substring(with: match.range(at: 1))), (-3_600_000...3_600_000).contains(parsed) {
                offset = parsed
            }
        }
        var grouped: [Int: [String]] = [:]
        for raw in lrc.components(separatedBy: .newlines) {
            let row = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: row.length))
            guard let last = matches.last else { continue }
            let text = row.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Int(row.substring(with: match.range(at: 1))) ?? 0
                let seconds = Int(row.substring(with: match.range(at: 2))) ?? 0
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? "" : row.substring(with: fractionRange)
                let milliseconds = Int((fraction + "000").prefix(3)) ?? 0
                let time = max(0, (minutes * 60 + seconds) * 1000 + milliseconds - offset)
                if !(grouped[time] ?? []).contains(text) { grouped[time, default: []].append(text) }
            }
        }
        let lines = grouped.keys.sorted().map { time in
            LyricLine(timeMS: time, text: (grouped[time] ?? []).filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }
        self.lines = lines
    }

    func activeLine(at milliseconds: Int) -> Int? {
        // Upper bound handles seeking backwards as well as normal playback.
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].timeMS <= milliseconds { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? nil : lines[low - 1].id
    }
}
