import Foundation
import Persistence
import SwiftData

/// The four colours the spec asks for.
public enum HighlightColor: String, Sendable, Hashable, Codable, CaseIterable {
    case yellow
    case green
    case blue
    case pink

    public var displayName: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        }
    }

    /// sRGB components, used for the mark on the page and the swatch.
    public var components: (r: Double, g: Double, b: Double) {
        switch self {
        case .yellow: (1.0, 0.85, 0.30)
        case .green: (0.55, 0.85, 0.52)
        case .blue: (0.50, 0.76, 0.96)
        case .pink: (1.0, 0.62, 0.75)
        }
    }
}

/// A highlight as the UI holds it.
public struct Highlight: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let itemID: String
    public var text: String
    public var note: String?
    public var color: HighlightColor
    public var locatorJSON: String
    public var progression: Double
    public var chapterTitle: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        itemID: String,
        text: String,
        note: String? = nil,
        color: HighlightColor,
        locatorJSON: String,
        progression: Double,
        chapterTitle: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemID = itemID
        self.text = text
        self.note = note
        self.color = color
        self.locatorJSON = locatorJSON
        self.progression = progression
        self.chapterTitle = chapterTitle
        self.createdAt = createdAt
    }
}

@ModelActor
public actor HighlightStore {
    public func highlights(serverID: UUID, itemID: String) throws -> [Highlight] {
        try modelContext.fetch(
            FetchDescriptor<HighlightRecord>(
                predicate: #Predicate { $0.serverID == serverID && $0.itemID == itemID },
                sortBy: [SortDescriptor(\.progression)]
            )
        ).map(Self.highlight(from:))
    }

    public func allHighlights(serverID: UUID) throws -> [Highlight] {
        try modelContext.fetch(
            FetchDescriptor<HighlightRecord>(
                predicate: #Predicate { $0.serverID == serverID },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        ).map(Self.highlight(from:))
    }

    public func add(_ highlight: Highlight, serverID: UUID) throws {
        modelContext.insert(HighlightRecord(
            id: highlight.id,
            serverID: serverID,
            itemID: highlight.itemID,
            text: highlight.text,
            note: highlight.note,
            colorRaw: highlight.color.rawValue,
            locatorJSON: highlight.locatorJSON,
            progression: highlight.progression,
            chapterTitle: highlight.chapterTitle,
            createdAt: highlight.createdAt
        ))
        try modelContext.save()
    }

    public func update(id: UUID, note: String?, color: HighlightColor?) throws {
        guard let record = try modelContext.fetch(
            FetchDescriptor<HighlightRecord>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        if let note { record.note = note.isEmpty ? nil : note }
        if let color { record.colorRaw = color.rawValue }
        record.updatedAt = .now
        try modelContext.save()
    }

    public func remove(id: UUID) throws {
        guard let record = try modelContext.fetch(
            FetchDescriptor<HighlightRecord>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    private static func highlight(from record: HighlightRecord) -> Highlight {
        Highlight(
            id: record.id,
            itemID: record.itemID,
            text: record.text,
            note: record.note,
            color: HighlightColor(rawValue: record.colorRaw) ?? .yellow,
            locatorJSON: record.locatorJSON,
            progression: record.progression,
            chapterTitle: record.chapterTitle,
            createdAt: record.createdAt
        )
    }
}

/// Turns highlights into a Markdown document.
///
/// Markdown because it is the format that survives: it opens in Obsidian,
/// Bear, Notion, a text editor and a terminal, and it will still open in
/// twenty years.
public enum HighlightMarkdownExporter {
    public static func markdown(
        bookTitle: String,
        author: String?,
        highlights: [Highlight],
        exportedAt: Date = .now
    ) -> String {
        var lines: [String] = ["# \(bookTitle)"]
        if let author, !author.isEmpty {
            lines.append("")
            lines.append("*\(author)*")
        }
        lines.append("")

        guard !highlights.isEmpty else {
            lines.append("_No highlights yet._")
            lines.append("")
            return lines.joined(separator: "\n")
        }

        let ordered = highlights.sorted { $0.progression < $1.progression }
        var lastChapter: String??

        for highlight in ordered {
            // A heading per chapter, but only when the chapter changes.
            if lastChapter != .some(highlight.chapterTitle) {
                lastChapter = .some(highlight.chapterTitle)
                if let chapter = highlight.chapterTitle, !chapter.isEmpty {
                    lines.append("## \(chapter)")
                    lines.append("")
                }
            }

            // Blockquote, with internal newlines kept as quoted lines so a
            // multi-paragraph highlight does not collapse.
            for line in highlight.text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("> \(line.trimmingCharacters(in: .whitespaces))")
            }
            if let note = highlight.note, !note.isEmpty {
                lines.append("")
                lines.append("**Note:** \(note)")
            }
            lines.append("")
            lines.append("— \(percentLabel(highlight.progression)) · \(highlight.color.displayName)")
            lines.append("")
        }

        lines.append("---")
        lines.append("")
        lines.append("Exported from Firelight on \(exportedAt.formatted(date: .long, time: .shortened)).")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func percentLabel(_ progression: Double) -> String {
        "\(Int((min(max(progression, 0), 1) * 100).rounded()))%"
    }

    /// A filename that will not upset a filesystem.
    public static func filename(forBookTitle title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let cleaned = title.unicodeScalars.filter { allowed.contains($0) }.map(Character.init)
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespaces)
        let safe = trimmed.isEmpty ? "Highlights" : trimmed
        return "\(safe) — Highlights.md"
    }
}
