import Foundation

/// Where the user is in one item, as of one moment on one device.
///
/// This is the unit the whole sync engine moves around. It covers audio and
/// ebook position together because a single ABS media-progress record does.
public struct ProgressPosition: Sendable, Hashable, Codable {
    public var itemID: String
    /// Set for a podcast episode; `nil` for a book.
    public var episodeID: String?

    /// Seconds into the audio. `nil` for an item with no audio.
    public var currentTime: TimeInterval?
    /// Total audio duration in seconds, as the server reported it.
    public var duration: TimeInterval?

    /// For EPUB, the Readium locator as JSON. For PDF and comics, the page
    /// number as a string. ABS stores this opaquely in `ebookLocation`.
    public var ebookLocation: String?
    /// 0...1 through the ebook.
    public var ebookProgress: Double?

    public var isFinished: Bool
    /// When this position was recorded, by the clock of the device that
    /// recorded it. The whole conflict rule turns on this value.
    public var updatedAt: Date
    public var deviceID: String
    public var deviceLabel: String

    public init(
        itemID: String,
        episodeID: String? = nil,
        currentTime: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        ebookLocation: String? = nil,
        ebookProgress: Double? = nil,
        isFinished: Bool = false,
        updatedAt: Date = .now,
        deviceID: String,
        deviceLabel: String
    ) {
        self.itemID = itemID
        self.episodeID = episodeID
        self.currentTime = currentTime
        self.duration = duration
        self.ebookLocation = ebookLocation
        self.ebookProgress = ebookProgress
        self.isFinished = isFinished
        self.updatedAt = updatedAt
        self.deviceID = deviceID
        self.deviceLabel = deviceLabel
    }

    /// Firelight's own key for a position: library item plus episode.
    ///
    /// This is deliberately *not* the ABS media-progress id — verified against
    /// `server/models/MediaProgress.js`, that is a random UUIDv4 and carries no
    /// meaning. ABS identifies progress by `libraryItemId` + `episodeId`, which
    /// is also what `PATCH /api/me/progress/:libraryItemId/:episodeId?` takes,
    /// so those two fields are what we key on locally.
    public var localKey: String {
        guard let episodeID else { return itemID }
        return "\(itemID)/\(episodeID)"
    }

    /// Fraction through the audio, when both numbers are known.
    public var audioProgress: Double? {
        guard let currentTime, let duration, duration > 0 else { return nil }
        return min(max(currentTime / duration, 0), 1)
    }

    /// True when this position says nothing about where the user is.
    public var isEmpty: Bool {
        currentTime == nil && ebookLocation == nil && ebookProgress == nil && !isFinished
    }
}
