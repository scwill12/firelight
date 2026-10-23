import ABSKit
import Foundation
import Observation
import Persistence

/// Owns every position change in the app.
///
/// The rule the whole app depends on: a position is written to the journal
/// *before* any network call, so nothing is ever lost to a tunnel, a crash or
/// a flat battery. Syncing drains that journal; it is never the source of truth.
@MainActor
@Observable
public final class ProgressSyncService {
    /// A conflict the user has to settle. The UI shows a prompt for this and
    /// nothing moves until they answer.
    public struct PendingConflict: Identifiable, Sendable, Equatable {
        public let id = UUID()
        public let itemID: String
        public let local: ProgressPosition
        public let remote: ProgressPosition
    }

    public private(set) var pendingConflict: PendingConflict?
    public private(set) var queuedCount = 0
    public private(set) var isSyncing = false
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let store: SwiftDataJournalStore?
    @ObservationIgnored private let resolver: ProgressConflictResolver
    @ObservationIgnored private let device: DeviceIdentity
    @ObservationIgnored private var clientProvider: @MainActor () -> ABSClient?
    @ObservationIgnored private var serverIDProvider: @MainActor () -> UUID?
    @ObservationIgnored private var currentSessionID: String?
    @ObservationIgnored private var sessionListening: Double = 0

    /// Applied when a conflict resolves in favour of the server, so the player
    /// can move there.
    public var onAdoptPosition: (@MainActor (ProgressPosition) -> Void)?

    public init(
        persistence: PersistenceController?,
        resolver: ProgressConflictResolver = ProgressConflictResolver(),
        device: DeviceIdentity = .cached(),
        client: @escaping @MainActor () -> ABSClient?,
        serverID: @escaping @MainActor () -> UUID?
    ) {
        self.store = persistence.map { SwiftDataJournalStore(modelContainer: $0.container) }
        self.resolver = resolver
        self.device = device
        self.clientProvider = client
        self.serverIDProvider = serverID
    }

    // MARK: - Recording

    /// Starts a new listening session, so offline entries group correctly.
    public func beginSession() {
        currentSessionID = UUID().uuidString
        sessionListening = 0
    }

    public func endSession() {
        currentSessionID = nil
        sessionListening = 0
    }

    /// Records a position. Always writes locally first.
    public func record(
        itemID: String,
        episodeID: String? = nil,
        currentTime: TimeInterval?,
        duration: TimeInterval?,
        ebookLocation: String? = nil,
        ebookProgress: Double? = nil,
        isFinished: Bool = false,
        listenedSinceLast: TimeInterval = 0
    ) async {
        guard let store, let serverID = serverIDProvider() else { return }
        sessionListening += max(0, listenedSinceLast)

        let position = ProgressPosition(
            itemID: itemID,
            episodeID: episodeID,
            currentTime: currentTime,
            duration: duration,
            ebookLocation: ebookLocation,
            ebookProgress: ebookProgress,
            isFinished: isFinished,
            updatedAt: .now,
            deviceID: device.id,
            deviceLabel: device.label
        )
        let entry = ProgressJournalEntry(
            serverID: serverID,
            position: position,
            origin: .local,
            sessionID: currentSessionID,
            timeListening: sessionListening
        )
        try? await store.append(entry)
        queuedCount = (try? await store.pendingEntries(limit: 500).count) ?? queuedCount
    }

    /// Takes in a position from the server or the socket and decides what to
    /// do with it. This is the only path by which a remote position can move
    /// the user.
    public func receiveRemote(_ position: ProgressPosition) async {
        guard let store, let serverID = serverIDProvider() else { return }
        let entry = ProgressJournalEntry(
            serverID: serverID,
            position: position,
            origin: .remote,
            syncState: .synced
        )
        let outcome = (try? await store.appendAndResolve(entry, resolver: resolver)) ?? .noChange

        switch outcome {
        case .takeRemote:
            onAdoptPosition?(position)
        case .ask(let local, let remote):
            pendingConflict = PendingConflict(itemID: position.itemID, local: local, remote: remote)
        case .keepLocal, .noChange:
            break
        }
    }

    /// The user chose which position to keep.
    public func resolveConflict(takingRemote: Bool) async {
        guard let conflict = pendingConflict else { return }
        pendingConflict = nil
        if takingRemote {
            onAdoptPosition?(conflict.remote)
        } else {
            // Keeping the local position means re-asserting it, or the next
            // sync would simply hand the server's position back.
            await record(
                itemID: conflict.local.itemID,
                episodeID: conflict.local.episodeID,
                currentTime: conflict.local.currentTime,
                duration: conflict.local.duration,
                ebookLocation: conflict.local.ebookLocation,
                ebookProgress: conflict.local.ebookProgress,
                isFinished: conflict.local.isFinished
            )
            await drain()
        }
    }

    // MARK: - Draining

    /// Sends everything pending. Safe to call often; it no-ops when there is
    /// nothing to do or no connection.
    public func drain() async {
        guard let store, let client = clientProvider(), !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let sessions = (try? await store.pendingSessions()) ?? []
        guard !sessions.isEmpty else {
            queuedCount = 0
            return
        }

        for (_, entries) in sessions {
            guard let last = entries.last, let first = entries.first else { continue }
            let ids = entries.map(\.id)
            do {
                // One offline session per group, then the position itself so
                // the user's place is right even if the session is rejected.
                if entries.count > 1 || first.sessionID != nil {
                    try await client.syncLocalSession(Self.localSession(from: entries, device: device))
                }
                try await client.updateProgress(
                    itemID: last.position.itemID,
                    episodeID: last.position.episodeID,
                    currentTime: last.position.currentTime,
                    duration: last.position.duration,
                    progress: last.position.audioProgress,
                    isFinished: last.position.isFinished,
                    ebookLocation: last.position.ebookLocation,
                    ebookProgress: last.position.ebookProgress
                )
                try? await store.markSynced(ids: ids)
            } catch let error as APIError where error.isTransient {
                // Leave it pending; the next drain will try again.
                break
            } catch {
                try? await store.markFailed(ids: ids)
            }
        }

        queuedCount = (try? await store.pendingEntries(limit: 500).count) ?? 0
        lastSyncedAt = .now
        try? await store.prune()
    }

    /// Pulls the server's progress and runs it through the resolver.
    public func reconcile(withServerProgress progress: [ABSMediaProgress]) async {
        for entry in progress {
            guard let itemID = entry.libraryItemId else { continue }
            let position = ProgressPosition(
                itemID: itemID,
                episodeID: entry.episodeId,
                currentTime: entry.currentTime,
                duration: entry.duration,
                ebookLocation: entry.ebookLocation,
                ebookProgress: entry.ebookProgress,
                isFinished: entry.isFinished ?? false,
                updatedAt: entry.lastUpdate ?? .distantPast,
                deviceID: "server",
                deviceLabel: "Audiobookshelf"
            )
            await receiveRemote(position)
            // One prompt at a time; the rest wait until it is answered.
            if pendingConflict != nil { return }
        }
    }

    /// Recomputes the streak and publishes it for the widget.
    ///
    /// Done here because this is the only place that can see the journal, and
    /// a widget cannot compute it for itself.
    public func refreshStreak() async {
        guard let store, let serverID = serverIDProvider() else { return }
        // A year is plenty: a streak longer than that is not going to be
        // broken by a window this wide.
        let since = Date.now.addingTimeInterval(-370 * 86_400)
        guard let days = try? await store.listeningDays(serverID: serverID, since: since) else { return }
        SharedState.listeningStreak = ListeningStreak().currentStreak(from: days)
        WidgetRefresher.reload()
    }

    /// Statistics for a period, built from the journal.
    public func stats(for period: ListeningStatsCalculator.Period) async -> ListeningStats? {
        guard let store, let serverID = serverIDProvider() else { return nil }
        let calculator = ListeningStatsCalculator()
        let range = calculator.range(for: period)

        guard let entries = try? await store.entriesForStats(serverID: serverID, since: range.lowerBound) else {
            return nil
        }
        return calculator.stats(
            from: entries.map {
                ListeningStatsCalculator.Sample(
                    itemID: $0.position.itemID,
                    position: $0.position.currentTime ?? 0,
                    at: $0.position.updatedAt,
                    isFinished: $0.position.isFinished
                )
            },
            in: range
        )
    }

    // MARK: - History

    /// Recent positions for one item, newest first, for the history screen.
    public func history(itemID: String, episodeID: String? = nil, limit: Int = 40) async -> [ProgressJournalEntry] {
        guard let store else { return [] }
        return (try? await store.entries(forItemID: itemID, episodeID: episodeID, limit: limit)) ?? []
    }

    public func latestPosition(itemID: String, episodeID: String? = nil) async -> ProgressPosition? {
        guard let store else { return nil }
        return try? await store.latestPosition(forItemID: itemID, episodeID: episodeID)
    }

    // MARK: - Private

    /// Builds the offline session ABS expects from a run of journal entries.
    nonisolated static func localSession(
        from entries: [ProgressJournalEntry],
        device: DeviceIdentity
    ) -> LocalPlaybackSession {
        let first = entries.first!
        let last = entries.last!
        return LocalPlaybackSession(
            id: first.sessionID ?? first.id.uuidString,
            libraryItemId: last.position.itemID,
            episodeId: last.position.episodeID,
            duration: last.position.duration ?? 0,
            deviceInfo: PlaybackSessionRequest.DeviceInfo(
                deviceId: device.id,
                clientName: "Firelight",
                clientVersion: Bundle.main.shortVersion,
                manufacturer: "Apple",
                model: device.label,
                sdkVersion: nil
            ),
            currentTime: last.position.currentTime ?? 0,
            // The total for the session, not a delta — ABS reads
            // `timeListening` here, unlike the in-session `/sync` call.
            timeListening: entries.map(\.timeListening).max() ?? 0,
            startTime: first.position.currentTime ?? 0,
            startedAt: first.position.updatedAt,
            updatedAt: last.position.updatedAt
        )
    }
}
