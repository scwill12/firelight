import Foundation
import SwiftData

/// A passage the reader marked, with an optional note.
///
/// Highlights are the user's own writing, not server data: ABS has nowhere to
/// put them. They live here and sync through iCloud in Phase 17, which is why
/// the record carries everything needed to rebuild it on another device.
/// Synced through iCloud, which constrains how it is declared.
///
/// **No `@Attribute(.unique)`**: CloudKit does not support unique constraints
/// and SwiftData refuses to build a CloudKit-backed container that has one.
/// Uniqueness is enforced by only ever inserting with a fresh `id`.
@Model
public final class HighlightRecord {
    // Every stored property carries a default. **CloudKit refuses to load a
    // store whose attributes are neither optional nor defaulted** — the error
    // arrives at runtime, when the container opens, not at compile time, so
    // the whole app fails to start rather than just sync.
    public var id: UUID = UUID()
    public var serverID: UUID = UUID()
    public var itemID: String = ""

    /// The text that was marked.
    public var text: String = ""
    public var note: String?
    /// `yellow`, `green`, `blue` or `pink`.
    public var colorRaw: String = "yellow"
    /// The Readium locator as JSON, for putting it back on the page.
    public var locatorJSON: String = "{}"
    /// 0...1 through the book, for ordering and for the export.
    public var progression: Double = 0
    /// The chapter or section it was in, for the export's headings.
    public var chapterTitle: String?
    public var createdAt: Date = Date.distantPast
    public var updatedAt: Date = Date.distantPast

    public init(
        id: UUID = UUID(),
        serverID: UUID,
        itemID: String,
        text: String,
        note: String? = nil,
        colorRaw: String,
        locatorJSON: String,
        progression: Double,
        chapterTitle: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.serverID = serverID
        self.itemID = itemID
        self.text = text
        self.note = note
        self.colorRaw = colorRaw
        self.locatorJSON = locatorJSON
        self.progression = progression
        self.chapterTitle = chapterTitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
