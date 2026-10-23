import Foundation

/// One durable record of a position change.
///
/// Spec: every position change is written locally, with a timestamp and a
/// device id, *before* any network call. The journal is the source of truth
/// while offline and the queue that drains when the server comes back.
public struct ProgressJournalEntry: Sendable, Hashable, Codable, Identifiable {
    public enum Origin: String, Sendable, Codable {
        /// Written by this device from playback or reading.
        case local
        /// Received from the server or the socket.
        case remote
    }

    public enum SyncState: String, Sendable, Codable {
        case pending
        case synced
        /// Rejected by the server; kept so it can be shown in diagnostics
        /// rather than silently dropped.
        case failed
    }

    public let id: UUID
    /// Which server this position belongs to. Two servers can hold the same
    /// book, and their progress is not interchangeable.
    public var serverID: UUID
    public var position: ProgressPosition
    public var origin: Origin
    public var syncState: SyncState
    /// When this entry was written locally, which may differ from
    /// `position.updatedAt` for an entry received from another device.
    public var recordedAt: Date
    public var attemptCount: Int
    /// Groups entries from one uninterrupted listen, so an offline stretch
    /// becomes one session for the server rather than hundreds.
    public var sessionID: String?
    /// Seconds listened in that session, for the server's statistics.
    public var timeListening: Double

    public init(
        id: UUID = UUID(),
        serverID: UUID,
        position: ProgressPosition,
        origin: Origin = .local,
        syncState: SyncState = .pending,
        recordedAt: Date = .now,
        attemptCount: Int = 0,
        sessionID: String? = nil,
        timeListening: Double = 0
    ) {
        self.id = id
        self.serverID = serverID
        self.position = position
        self.origin = origin
        self.syncState = syncState
        self.recordedAt = recordedAt
        self.attemptCount = attemptCount
        self.sessionID = sessionID
        self.timeListening = timeListening
    }
}

/// Storage for the journal. Phase 4 implements this on SwiftData; tests use an
/// in-memory double. Nothing in the app writes a position except through here.
public protocol ProgressJournalStore: Sendable {
    func append(_ entry: ProgressJournalEntry) async throws
    /// Most recent first.
    func entries(forItemID itemID: String, episodeID: String?, limit: Int) async throws -> [ProgressJournalEntry]
    func pendingEntries(limit: Int) async throws -> [ProgressJournalEntry]
    func markSynced(ids: [UUID]) async throws
    func markFailed(ids: [UUID]) async throws
    /// The position the app should act on for an item right now.
    func latestPosition(forItemID itemID: String, episodeID: String?) async throws -> ProgressPosition?
}
