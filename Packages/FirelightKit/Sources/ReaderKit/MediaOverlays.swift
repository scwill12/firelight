import Foundation

/// Read-along support, as Storyteller produces it.
///
/// Storyteller aligns an audiobook to its ebook and writes the result as EPUB
/// 3 media overlays: a SMIL file per chapter, mapping text fragments to audio
/// timestamps. Detecting them is what decides whether the reader offers to
/// read along at all.
public enum MediaOverlays {
    /// One sentence or phrase, and when it is spoken.
    public struct Fragment: Sendable, Hashable, Identifiable {
        /// The id of the element in the XHTML.
        public let textID: String
        public let start: TimeInterval
        public let end: TimeInterval
        public var id: String { textID }

        public init(textID: String, start: TimeInterval, end: TimeInterval) {
            self.textID = textID
            self.start = start
            self.end = end
        }

        public func contains(_ time: TimeInterval) -> Bool {
            time >= start && time < end
        }
    }

    /// Parses a SMIL file into fragments.
    ///
    /// Written by hand rather than with a full XML parser because a SMIL
    /// overlay is a flat list of `<par>` elements with two children, and the
    /// clip times are the only part that needs care.
    public static func fragments(fromSMIL xml: String) -> [Fragment] {
        var fragments: [Fragment] = []

        // Each <par> pairs a text fragment with an audio clip.
        for par in xml.components(separatedBy: "<par").dropFirst() {
            guard let body = par.components(separatedBy: "</par>").first else { continue }
            guard let textSrc = attribute("src", in: body, after: "<text"),
                  let fragment = textSrc.split(separator: "#").last.map(String.init),
                  let begin = attribute("clipBegin", in: body, after: "<audio"),
                  let end = attribute("clipEnd", in: body, after: "<audio"),
                  let start = seconds(fromClockValue: begin),
                  let finish = seconds(fromClockValue: end)
            else { continue }
            fragments.append(Fragment(textID: fragment, start: start, end: finish))
        }
        return fragments.sorted { $0.start < $1.start }
    }

    static func attribute(_ name: String, in text: String, after element: String) -> String? {
        guard let elementRange = text.range(of: element) else { return nil }
        let tail = text[elementRange.upperBound...]
        guard let close = tail.firstIndex(of: ">") else { return nil }
        let tag = String(tail[tail.startIndex..<close])

        guard let nameRange = tag.range(of: "\(name)=") else { return nil }
        let afterName = tag[nameRange.upperBound...]
        guard let quote = afterName.first, quote == "\"" || quote == "'" else { return nil }
        let valueStart = afterName.index(after: afterName.startIndex)
        guard let valueEnd = afterName[valueStart...].firstIndex(of: quote) else { return nil }
        return String(afterName[valueStart..<valueEnd])
    }

    /// SMIL clock values: `12.5s`, `0:00:12.5`, `00:12.5`, or bare seconds.
    public static func seconds(fromClockValue value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("ms") {
            return Double(trimmed.dropLast(2)).map { $0 / 1000 }
        }
        if trimmed.hasSuffix("s") {
            return Double(trimmed.dropLast())
        }
        if trimmed.hasSuffix("min") {
            return Double(trimmed.dropLast(3)).map { $0 * 60 }
        }
        if trimmed.hasSuffix("h") {
            return Double(trimmed.dropLast()).map { $0 * 3600 }
        }

        let parts = trimmed.split(separator: ":").map(String.init)
        switch parts.count {
        case 1:
            return Double(parts[0])
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        case 3:
            guard let hours = Double(parts[0]), let minutes = Double(parts[1]),
                  let seconds = Double(parts[2]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds
        default:
            return nil
        }
    }

    /// Which fragment is being spoken, for highlighting as the audio plays.
    public static func fragment(at time: TimeInterval, in fragments: [Fragment]) -> Fragment? {
        // Fragments are sorted, so a binary search keeps this cheap enough to
        // run on every tick.
        var low = 0
        var high = fragments.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let fragment = fragments[middle]
            if fragment.contains(time) { return fragment }
            if time < fragment.start { high = middle - 1 } else { low = middle + 1 }
        }
        return nil
    }
}
