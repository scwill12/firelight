import Foundation
import SwiftData

/// One durable record of a position change.
///
/// This is the most important table in the app. Every position change is
/// written here, with a timestamp and a device id, *before* any network call —
/// so a crash, a dead battery or a tunnel cannot lose someone's place.
/// Entries are kept after syncing, because they are also the position history.
@Model
public final class JournalEntryRecord {
    @Attribute(.unique) public var id: UUID
    public var serverID: UUID
    public var itemID: String
    public var episodeID: String?

    public var currentTime: Double
    public var duration: Double
    public var ebookLocation: String?
    public var ebookProgress: Double?
    public var isFinished: Bool

    /// When the position was reached, by the clock of the device that reached
    /// it. The conflict rule turns on this value, not on `recordedAt`.
    public var positionUpdatedAt: Date
    public var deviceID: String
    public var deviceLabel: String

    /// `local` or `remote`.
    public var originRaw: String
    /// `pending`, `synced` or `failed`.
    public var syncStateRaw: String
    public var recordedAt: Date
    public var attemptCount: Int

    /// Groups entries from one uninterrupted listen, so they can be reported
    /// to ABS as a single offline session rather than hundreds of them.
    public var sessionID: String?
    /// Seconds actually listened in this session, for the server's statistics.
    public var timeListening: Double

    public init(
        id: UUID = UUID(),
        serverID: UUID,
        itemID: String,
        episodeID: String? = nil,
        currentTime: Double,
        duration: Double,
        ebookLocation: String? = nil,
        ebookProgress: Double? = nil,
        isFinished: Bool = false,
        positionUpdatedAt: Date,
        deviceID: String,
        deviceLabel: String,
        originRaw: String,
        syncStateRaw: String,
        recordedAt: Date = .now,
        attemptCount: Int = 0,
        sessionID: String? = nil,
        timeListening: Double = 0
    ) {
        self.id = id
        self.serverID = serverID
        self.itemID = itemID
        self.episodeID = episodeID
        self.currentTime = currentTime
        self.duration = duration
        self.ebookLocation = ebookLocation
        self.ebookProgress = ebookProgress
        self.isFinished = isFinished
        self.positionUpdatedAt = positionUpdatedAt
        self.deviceID = deviceID
        self.deviceLabel = deviceLabel
        self.originRaw = originRaw
        self.syncStateRaw = syncStateRaw
        self.recordedAt = recordedAt
        self.attemptCount = attemptCount
        self.sessionID = sessionID
        self.timeListening = timeListening
    }
}
