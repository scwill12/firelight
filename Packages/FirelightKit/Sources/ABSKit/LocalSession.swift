import Foundation

/// A listen that happened while offline, in the shape ABS expects back.
///
/// Verified against `PlaybackSessionManager.syncLocalSession`. Two traps:
///  - A local session carries **`timeListening`** (the total for the session),
///    while an in-session `/sync` carries **`timeListened`** (the delta since
///    the last report). Sending the wrong one silently corrupts listening
///    stats.
///  - ABS replaces any `id` beginning with `play_local_`, so Firelight sends a
///    UUID it generated and keeps it, which is what lets the same offline
///    session be topped up across several reconnects instead of duplicated.
public struct LocalPlaybackSession: Sendable, Hashable, Codable {
    public var id: String
    public var libraryItemId: String
    public var episodeId: String?
    public var bookId: String?
    public var libraryId: String?
    public var displayTitle: String?
    public var displayAuthor: String?
    public var coverPath: String?
    public var duration: Double
    public var playMethod: Int
    public var mediaPlayer: String
    public var deviceInfo: PlaybackSessionRequest.DeviceInfo
    public var currentTime: Double
    /// The running total for this session, not a delta.
    public var timeListening: Double
    public var startTime: Double
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        libraryItemId: String,
        episodeId: String? = nil,
        bookId: String? = nil,
        libraryId: String? = nil,
        displayTitle: String? = nil,
        displayAuthor: String? = nil,
        coverPath: String? = nil,
        duration: Double,
        playMethod: Int = 0,
        mediaPlayer: String = "AVPlayer",
        deviceInfo: PlaybackSessionRequest.DeviceInfo,
        currentTime: Double,
        timeListening: Double,
        startTime: Double,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.libraryItemId = libraryItemId
        self.episodeId = episodeId
        self.bookId = bookId
        self.libraryId = libraryId
        self.displayTitle = displayTitle
        self.displayAuthor = displayAuthor
        self.coverPath = coverPath
        self.duration = duration
        self.playMethod = playMethod
        self.mediaPlayer = mediaPlayer
        self.deviceInfo = deviceInfo
        self.currentTime = currentTime
        self.timeListening = timeListening
        self.startTime = startTime
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}
