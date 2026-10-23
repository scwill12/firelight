import Foundation

/// One library on the server.
///
/// `GET /api/libraries` wraps these in an object — note the `libraries` key.
public struct ABSLibrary: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    /// `book` or `podcast`.
    public let mediaType: String?
    public let icon: String?
    public let displayOrder: Int?

    public var isPodcast: Bool { mediaType == "podcast" }
}

public struct ABSLibrariesResponse: Sendable, Codable {
    public let libraries: [ABSLibrary]
}

/// A book's metadata, as the minified serializer sends it.
///
/// Verified against `Book.oldMetadataToJSONMinified()`. Everything is optional:
/// a library full of loose MP3s has almost none of it, and a client that
/// insists on a title will fail to show half of someone's shelf.
public struct ABSBookMetadata: Sendable, Hashable, Codable {
    public let title: String?
    /// Title with a leading article moved to the end, which is what ABS sorts
    /// on — "Hobbit, The". Use it for sorting, never for display.
    public let titleIgnorePrefix: String?
    public let subtitle: String?
    public let authorName: String?
    public let authorNameLF: String?
    public let narratorName: String?
    /// A display string like "Discworld #5", not a structured series link.
    public let seriesName: String?
    public let genres: [String]?
    public let publishedYear: String?
    public let publisher: String?
    public let description: String?
    public let isbn: String?
    public let asin: String?
    public let language: String?
    public let explicit: Bool?
    public let abridged: Bool?
}

/// The `media` object of a book library item.
///
/// Verified against `Book.toOldJSONMinified()`.
public struct ABSBookMedia: Sendable, Hashable, Codable {
    public let id: String?
    public let metadata: ABSBookMetadata
    public let coverPath: String?
    public let tags: [String]?
    public let numTracks: Int?
    public let numAudioFiles: Int?
    public let numChapters: Int?
    /// Seconds.
    public let duration: Double?
    public let size: Int64?
    /// `epub`, `pdf`, `mobi`… or absent when there is no ebook.
    public let ebookFormat: String?
}

/// A library item.
///
/// Verified against `LibraryItem.toOldJSONMinified()`. `addedAt` and
/// `updatedAt` are epoch milliseconds, which `ABSJSON.decoder` handles.
public struct ABSLibraryItem: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let libraryId: String?
    public let mediaType: String?
    public let addedAt: Date?
    public let updatedAt: Date?
    public let isMissing: Bool?
    public let isInvalid: Bool?
    public let numFiles: Int?
    public let size: Int64?
    public let media: ABSBookMedia?
    /// Present only when the server collapsed a series into one row.
    public let collapsedSeries: CollapsedSeries?

    public struct CollapsedSeries: Sendable, Hashable, Codable {
        public let id: String?
        public let name: String?
        public let numBooks: Int?
    }

    public var hasAudio: Bool { (media?.numTracks ?? 0) > 0 }
    public var hasEbook: Bool { media?.ebookFormat?.isEmpty == false }
}

/// `GET /api/libraries/:id/items`.
///
/// `total` is omitted on the collapsed-subseries path, so it is optional —
/// decoding it as required would fail exactly for users who group by series.
public struct ABSLibraryItemsPage: Sendable, Codable {
    public let results: [ABSLibraryItem]
    public let total: Int?
    public let limit: Int?
    public let page: Int?
}

/// `GET /api/libraries/:id/series`.
public struct ABSSeries: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String?
    public let description: String?
    public let books: [ABSLibraryItem]?
}

public struct ABSSeriesPage: Sendable, Codable {
    public let results: [ABSSeries]
    public let total: Int?
}

/// `GET /api/libraries/:id/search`.
public struct ABSSearchResults: Sendable, Codable {
    public struct ItemMatch: Sendable, Codable {
        public let libraryItem: ABSLibraryItem
        public let matchKey: String?
        public let matchText: String?
    }
    public struct SeriesMatch: Sendable, Codable {
        public let series: ABSSeries?
        public let books: [ABSLibraryItem]?
    }

    public let book: [ItemMatch]?
    public let podcast: [ItemMatch]?
    public let series: [SeriesMatch]?
    public let authors: [ABSAuthor]?
}

public struct ABSAuthor: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String?
    public let numBooks: Int?
}

/// One progress record from `GET /api/me`.
///
/// Verified against `MediaProgress.getOldMediaProgress()`. The `id` is a random
/// UUID and carries no meaning — progress is identified by `libraryItemId`
/// plus `episodeId`.
public struct ABSMediaProgress: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let libraryItemId: String?
    public let episodeId: String?
    /// Seconds.
    public let duration: Double?
    /// 0...1.
    public let progress: Double?
    /// Seconds.
    public let currentTime: Double?
    public let isFinished: Bool?
    public let hideFromContinueListening: Bool?
    public let ebookLocation: String?
    public let ebookProgress: Double?
    public let lastUpdate: Date?
    public let startedAt: Date?
    public let finishedAt: Date?
}

/// `GET /api/me` — the fields Phase 2 needs. The same endpoint carries
/// bookmarks and permissions, which later phases decode.
public struct ABSMe: Sendable, Codable {
    public let id: String
    public let username: String
    public let type: String?
    public let mediaProgress: [ABSMediaProgress]?
}
