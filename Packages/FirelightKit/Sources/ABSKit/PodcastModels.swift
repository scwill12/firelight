import Foundation

/// A podcast's metadata.
///
/// Verified against `Podcast.oldMetadataToJSONExpanded()`. Note it is `author`
/// here, not `authorName` as on a book — decoding a podcast with the book
/// model silently loses the author, which is what happened before Phase 11.
public struct ABSPodcastMetadata: Sendable, Hashable, Codable {
    public let title: String?
    public let titleIgnorePrefix: String?
    public let author: String?
    public let description: String?
    public let releaseDate: String?
    public let genres: [String]?
    public let feedUrl: String?
    public let imageUrl: String?
    public let itunesPageUrl: String?
    public let itunesId: String?
    public let explicit: Bool?
    public let language: String?
    public let type: String?
}

/// The `media` object of a podcast library item.
///
/// Verified against `Podcast.toOldJSONMinified()` / `toOldJSONExpanded()`.
/// `episodes` is present only on the expanded form.
public struct ABSPodcastMedia: Sendable, Hashable, Codable {
    public let id: String?
    public let metadata: ABSPodcastMetadata
    public let coverPath: String?
    public let tags: [String]?
    public let numEpisodes: Int?
    public let autoDownloadEpisodes: Bool?
    public let autoDownloadSchedule: String?
    public let lastEpisodeCheck: Date?
    public let maxEpisodesToKeep: Int?
    public let maxNewEpisodesToDownload: Int?
    public let size: Int64?
    public let episodes: [ABSPodcastEpisode]?
}

/// One episode.
///
/// Verified against `PodcastEpisode.toOldJSON()` / `toOldJSONExpanded()`.
/// `audioTrack`, `size` and `duration` appear only on the expanded form — an
/// episode list from the library gives you none of them.
public struct ABSPodcastEpisode: Sendable, Hashable, Codable, Identifiable {
    public struct Enclosure: Sendable, Hashable, Codable {
        public let url: String?
        public let type: String?
        /// A string, because ABS stringifies a BigInt here.
        public let length: String?

        public var bytes: Int64? { length.flatMap(Int64.init) }
    }

    public let id: String
    public let libraryItemId: String?
    public let podcastId: String?
    public let index: Int?
    public let season: String?
    public let episode: String?
    public let episodeType: String?
    public let title: String?
    public let subtitle: String?
    public let description: String?
    public let enclosure: Enclosure?
    public let guid: String?
    public let pubDate: String?
    public let chapters: [ABSChapter]?
    public let publishedAt: Date?
    public let addedAt: Date?
    public let updatedAt: Date?

    // Expanded only.
    public let audioTrack: ABSAudioTrack?
    public let size: Int64?
    public let duration: Double?

    /// Best available length, falling back to the enclosure's byte count.
    public var sizeBytes: Int64? { size ?? enclosure?.bytes }

    /// "S2E14", "Episode 14", or nothing.
    public var numbering: String? {
        switch (season, episode) {
        case let (.some(season), .some(episode)) where !season.isEmpty && !episode.isEmpty:
            "S\(season)E\(episode)"
        case let (_, .some(episode)) where !episode.isEmpty:
            "Episode \(episode)"
        default:
            nil
        }
    }
}

/// A podcast library item.
///
/// Separate from `ABSLibraryItem` because `media` is a different shape — the
/// two share only their outer wrapper.
public struct ABSPodcastItem: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let libraryId: String?
    public let mediaType: String?
    public let addedAt: Date?
    public let updatedAt: Date?
    public let isMissing: Bool?
    public let size: Int64?
    public let media: ABSPodcastMedia?
}

public struct ABSPodcastItemsPage: Sendable, Codable {
    public let results: [ABSPodcastItem]
    public let total: Int?
    public let limit: Int?
    public let page: Int?
}

/// `GET /api/libraries/:id/recent-episodes`.
public struct ABSRecentEpisodesPage: Sendable, Codable {
    public let episodes: [ABSPodcastEpisode]?
    public let total: Int?
}
