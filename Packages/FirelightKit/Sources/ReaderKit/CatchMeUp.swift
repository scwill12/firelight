import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Summarises what has happened so far.
///
/// The hard rule is that **nothing past the reader's current position may be
/// included**. A summary that spoils the next chapter is worse than no summary
/// at all, so the text is cut before it ever reaches the model, and that
/// cutting is the part worth testing.
public struct CatchMeUp: Sendable {
    /// One chapter's text, in reading order.
    public struct Chapter: Sendable, Hashable {
        public let title: String?
        public let text: String
        /// Where this chapter starts, 0...1 through the book.
        public let startProgression: Double
        /// Where it ends.
        public let endProgression: Double

        public init(title: String?, text: String, startProgression: Double, endProgression: Double) {
            self.title = title
            self.text = text
            self.startProgression = startProgression
            self.endProgression = endProgression
        }
    }

    /// How many chapters back to look.
    public var chapterCount: Int
    /// Roughly how much text the model is given at once. Characters rather
    /// than tokens because the exact tokenizer is not ours to know; four
    /// characters per token is the usual rule of thumb.
    public var chunkCharacters: Int

    public init(chapterCount: Int = 3, chunkCharacters: Int = 6000) {
        self.chapterCount = chapterCount
        self.chunkCharacters = chunkCharacters
    }

    /// The text to summarise: the last few chapters, truncated at the reader's
    /// position.
    public func text(from chapters: [Chapter], upTo progression: Double) -> String {
        let position = min(max(progression, 0), 1)

        // Everything the reader has actually reached.
        let reached = chapters.filter { $0.startProgression < position }
        guard !reached.isEmpty else { return "" }

        let recent = reached.suffix(chapterCount)
        return recent.map { chapter in
            // The chapter the reader is inside gets cut at their position.
            guard chapter.endProgression > position else { return chapter.text }
            let span = chapter.endProgression - chapter.startProgression
            guard span > 0 else { return "" }
            let fraction = (position - chapter.startProgression) / span
            return Self.prefix(of: chapter.text, fraction: fraction)
        }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Takes the first `fraction` of a chapter, ending on a sentence so the
    /// model is not handed half a clause.
    static func prefix(of text: String, fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return "" }
        guard clamped < 1 else { return text }

        let limit = Int(Double(text.count) * clamped)
        guard limit > 0, limit < text.count else { return clamped >= 1 ? text : "" }

        let cut = text.index(text.startIndex, offsetBy: limit)
        let candidate = String(text[text.startIndex..<cut])

        // Back up to the last sentence ending, when there is one worth using.
        if let lastStop = candidate.lastIndex(where: { ".!?".contains($0) }) {
            let sentence = String(candidate[candidate.startIndex...lastStop])
            if sentence.count > candidate.count / 2 { return sentence }
        }
        return candidate
    }

    /// Splits text into pieces the model can take one at a time, breaking on
    /// paragraphs so a chunk is never half a sentence.
    public func chunks(of text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > chunkCharacters else { return [text] }

        var chunks: [String] = []
        var current = ""

        for paragraph in text.components(separatedBy: "\n\n") {
            if current.count + paragraph.count + 2 > chunkCharacters, !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            }
            // A single paragraph longer than a chunk is split on its own.
            if paragraph.count > chunkCharacters {
                var remainder = Substring(paragraph)
                while remainder.count > chunkCharacters {
                    let cut = remainder.index(remainder.startIndex, offsetBy: chunkCharacters)
                    chunks.append(String(remainder[remainder.startIndex..<cut]))
                    remainder = remainder[cut...]
                }
                current = String(remainder)
            } else {
                current += (current.isEmpty ? "" : "\n\n") + paragraph
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return chunks
    }
}

/// Whether the feature can run at all, and running it.
@MainActor
public final class CatchMeUpService {
    public enum Availability: Sendable, Equatable {
        case available
        case noAppleIntelligence
        case notEnabled
        case notReady
        case unsupportedDevice

        public var canRun: Bool { self == .available }

        /// What the user is told. Never "an error occurred".
        public var message: String? {
            switch self {
            case .available: nil
            case .noAppleIntelligence: "This device doesn't have Apple Intelligence."
            case .notEnabled: "Turn on Apple Intelligence in Settings to use this."
            case .notReady: "Apple Intelligence is still getting ready."
            case .unsupportedDevice: "This device can't run Apple Intelligence."
            }
        }
    }

    public init() {}

    public var availability: Availability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return .noAppleIntelligence }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .notReady
            case .deviceNotEligible: return .unsupportedDevice
            @unknown default: return .noAppleIntelligence
            }
        @unknown default:
            return .noAppleIntelligence
        }
        #else
        return .noAppleIntelligence
        #endif
    }

    /// Summarises the text, a chunk at a time, then summarises the summaries.
    ///
    /// Everything stays on the device: this is the whole reason the feature
    /// uses the system model rather than a service.
    public func summarise(_ text: String, using catchMeUp: CatchMeUp = CatchMeUp()) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), availability.canRun else {
            throw ReaderError.fileUnreadable
        }

        let chunks = catchMeUp.chunks(of: text)
        guard !chunks.isEmpty else { return "" }

        let instructions = """
        You are summarising part of a book for a reader who has put it down \
        and come back. Write a short, plain recap of what happened. Do not \
        speculate about what happens next. Do not mention that you are \
        summarising.
        """

        var partials: [String] = []
        for chunk in chunks {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: chunk)
            partials.append(response.content)
        }

        guard partials.count > 1 else { return partials[0] }

        let session = LanguageModelSession(instructions: """
        Combine these partial recaps of a book into one short recap, in \
        reading order. Keep it to a few sentences.
        """)
        return try await session.respond(to: partials.joined(separator: "\n\n")).content
        #else
        throw ReaderError.fileUnreadable
        #endif
    }
}
