import Foundation
import SwiftData

/// One cached podcast episode.
///
/// Episodes are cached separately from their show: a podcast library item is
/// one row with hundreds of episodes behind it, and the episode list is what
/// people actually scroll.
@Model
public final class CachedEpisode {
    /// `serverID:itemID:episodeID`.
    @Attribute(.unique) public var compositeID: String
    public var serverID: UUID
    public var itemID: String
    public var episodeID: String

    public var title: String
    public var subtitle: String?
    public var summary: String?
    public var numbering: String?
    public var duration: Double
    public var sizeBytes: Int64
    public var publishedAt: Date?
    public var addedAt: Date
    /// Index within the feed, for ordering when there are no dates.
    public var feedIndex: Int

    public var progressCurrentTime: Double
    public var progressFraction: Double
    public var isFinished: Bool
    public var progressLastUpdate: Date?

    public init(
        serverID: UUID,
        itemID: String,
        episodeID: String,
        title: String,
        subtitle: String? = nil,
        summary: String? = nil,
        numbering: String? = nil,
        duration: Double = 0,
        sizeBytes: Int64 = 0,
        publishedAt: Date? = nil,
        addedAt: Date = .now,
        feedIndex: Int = 0
    ) {
        self.compositeID = "\(serverID.uuidString):\(itemID):\(episodeID)"
        self.serverID = serverID
        self.itemID = itemID
        self.episodeID = episodeID
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.numbering = numbering
        self.duration = duration
        self.sizeBytes = sizeBytes
        self.publishedAt = publishedAt
        self.addedAt = addedAt
        self.feedIndex = feedIndex
        self.progressCurrentTime = 0
        self.progressFraction = 0
        self.isFinished = false
        self.progressLastUpdate = nil
    }
}

/// One entry in Up Next. A book has no episode; an episode has both.
public struct QueueEntry: Sendable, Hashable, Codable, Identifiable {
    public let itemID: String
    public let episodeID: String?
    public let title: String
    public let subtitle: String?

    public var id: String { episodeID.map { "\(itemID)/\($0)" } ?? itemID }

    public init(itemID: String, episodeID: String? = nil, title: String, subtitle: String? = nil) {
        self.itemID = itemID
        self.episodeID = episodeID
        self.title = title
        self.subtitle = subtitle
    }
}

public extension SharedState {
    private static var queueKey: String { "firelight.shared.upNext" }

    /// Up Next, which deliberately mixes books and episodes — the spec asks
    /// for one queue, not two.
    static var upNext: [QueueEntry] {
        get {
            guard let data = AppGroup.defaults?.data(forKey: queueKey) else { return [] }
            return (try? JSONDecoder().decode([QueueEntry].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            AppGroup.defaults?.set(data, forKey: queueKey)
        }
    }
}
