import Foundation
import SwiftData

/// A library, cached so the app can draw a shelf before any network call.
@Model
public final class CachedLibrary {
    /// `serverID:libraryID` — ABS ids are only unique within a server.
    @Attribute(.unique) public var compositeID: String
    public var serverID: UUID
    public var libraryID: String
    public var name: String
    public var mediaType: String?
    public var displayOrder: Int
    public var lastRefreshedAt: Date?

    public init(
        serverID: UUID,
        libraryID: String,
        name: String,
        mediaType: String?,
        displayOrder: Int,
        lastRefreshedAt: Date? = nil
    ) {
        self.compositeID = "\(serverID.uuidString):\(libraryID)"
        self.serverID = serverID
        self.libraryID = libraryID
        self.name = name
        self.mediaType = mediaType
        self.displayOrder = displayOrder
        self.lastRefreshedAt = lastRefreshedAt
    }
}

/// One library item, flattened.
///
/// Flattened rather than mirroring the ABS object graph because every screen
/// in the app wants to sort and filter on these fields, and a nested blob
/// cannot be queried. The server's progress lives here too; Phase 4 adds the
/// local journal that overrides it.
@Model
public final class CachedItem {
    @Attribute(.unique) public var compositeID: String
    public var serverID: UUID
    public var itemID: String
    public var libraryID: String

    public var title: String
    /// Title the way ABS sorts it ("Hobbit, The"). Never displayed.
    public var sortTitle: String
    public var subtitle: String?
    public var author: String?
    public var narrator: String?
    /// The raw display string, e.g. "Discworld #5".
    public var seriesName: String?
    /// "Discworld" — the part without the number, for grouping.
    public var seriesBaseName: String?
    /// 5 — for ordering a series correctly. `nil` when unnumbered.
    public var seriesSequence: Double?
    /// Comma-joined, so search can match without a join table.
    public var genresText: String
    /// Title, author, narrator, series and genres in one lowercased string.
    ///
    /// A `#Predicate` that ORs five `localizedStandardContains` calls defeats
    /// the type checker, and five separate fetches would be slower anyway. One
    /// denormalised field makes search a single comparison.
    public var searchText: String
    public var publishedYear: String?
    public var summary: String?

    /// Seconds.
    public var duration: Double
    public var sizeBytes: Int64
    public var numChapters: Int
    public var ebookFormat: String?
    public var hasAudio: Bool
    public var coverPath: String?
    public var mediaType: String
    public var isMissing: Bool

    public var addedAt: Date
    public var updatedAt: Date

    // The server's view of progress.
    public var progressCurrentTime: Double
    /// 0...1.
    public var progressFraction: Double
    public var progressIsFinished: Bool
    public var progressLastUpdate: Date?
    public var progressStartedAt: Date?
    /// The user asked ABS to stop showing this under Continue.
    public var progressHidden: Bool

    public init(
        serverID: UUID,
        itemID: String,
        libraryID: String,
        title: String,
        sortTitle: String,
        subtitle: String? = nil,
        author: String? = nil,
        narrator: String? = nil,
        seriesName: String? = nil,
        seriesBaseName: String? = nil,
        seriesSequence: Double? = nil,
        genresText: String = "",
        publishedYear: String? = nil,
        summary: String? = nil,
        duration: Double = 0,
        sizeBytes: Int64 = 0,
        numChapters: Int = 0,
        ebookFormat: String? = nil,
        hasAudio: Bool = false,
        coverPath: String? = nil,
        mediaType: String = "book",
        isMissing: Bool = false,
        addedAt: Date = .distantPast,
        updatedAt: Date = .distantPast
    ) {
        self.compositeID = "\(serverID.uuidString):\(itemID)"
        self.serverID = serverID
        self.itemID = itemID
        self.libraryID = libraryID
        self.title = title
        self.sortTitle = sortTitle
        self.subtitle = subtitle
        self.author = author
        self.narrator = narrator
        self.seriesName = seriesName
        self.seriesBaseName = seriesBaseName
        self.seriesSequence = seriesSequence
        self.genresText = genresText
        self.searchText = CachedItem.makeSearchText(
            title: title,
            author: author,
            narrator: narrator,
            seriesName: seriesName,
            genresText: genresText
        )
        self.publishedYear = publishedYear
        self.summary = summary
        self.duration = duration
        self.sizeBytes = sizeBytes
        self.numChapters = numChapters
        self.ebookFormat = ebookFormat
        self.hasAudio = hasAudio
        self.coverPath = coverPath
        self.mediaType = mediaType
        self.isMissing = isMissing
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.progressCurrentTime = 0
        self.progressFraction = 0
        self.progressIsFinished = false
        self.progressLastUpdate = nil
        self.progressStartedAt = nil
        self.progressHidden = false
    }
}

public extension CachedItem {
    /// Everything searchable, lowercased and folded so "bronte" finds "Brontë".
    static func makeSearchText(
        title: String,
        author: String?,
        narrator: String?,
        seriesName: String?,
        genresText: String
    ) -> String {
        [title, author ?? "", narrator ?? "", seriesName ?? "", genresText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    func refreshSearchText() {
        searchText = CachedItem.makeSearchText(
            title: title,
            author: author,
            narrator: narrator,
            seriesName: seriesName,
            genresText: genresText
        )
    }
}

/// Splits "Discworld #5" into a name and a number.
///
/// ABS's minified payload gives the series only as a display string, so this
/// is the only way to order a series correctly without a second request per
/// book. Decimal sequences ("#2.5" for a novella) are common and must survive.
public enum SeriesNameParser {
    public static func parse(_ raw: String?) -> (name: String?, sequence: Double?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }
        guard let hashIndex = raw.lastIndex(of: "#") else { return (raw, nil) }

        let name = raw[raw.startIndex..<hashIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let numberText = raw[raw.index(after: hashIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sequence = Double(numberText) else { return (raw, nil) }
        return (name.isEmpty ? raw : name, sequence)
    }
}
