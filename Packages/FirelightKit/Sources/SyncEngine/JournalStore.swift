import Foundation
import Persistence
import SwiftData

/// The journal, on SwiftData.
///
/// Writes land here before any network call; nothing in the app changes a
/// position except through this actor.
@ModelActor
public actor SwiftDataJournalStore: ProgressJournalStore {
    public func append(_ entry: ProgressJournalEntry) async throws {
        modelContext.insert(Self.record(from: entry))
        try modelContext.save()
    }

    /// Appends and returns what the app should act on, having resolved the new
    /// entry against what was already known.
    public func appendAndResolve(
        _ entry: ProgressJournalEntry,
        resolver: ProgressConflictResolver
    ) async throws -> ProgressConflictOutcome {
        let existing = try currentPosition(
            forItemID: entry.position.itemID,
            episodeID: entry.position.episodeID
        )
        modelContext.insert(Self.record(from: entry))
        try modelContext.save()

        // A position this device just produced is not in conflict with itself.
        guard entry.origin == .remote else { return .noChange }
        return resolver.resolve(local: existing, remote: entry.position)
    }

    public func entries(forItemID itemID: String, episodeID: String?, limit: Int) async throws -> [ProgressJournalEntry] {
        var descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: Self.predicate(itemID: itemID, episodeID: episodeID),
            sortBy: [SortDescriptor(\.positionUpdatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(Self.entry(from:))
    }

    public func pendingEntries(limit: Int) async throws -> [ProgressJournalEntry] {
        let pending = ProgressJournalEntry.SyncState.pending.rawValue
        var descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.syncStateRaw == pending },
            sortBy: [SortDescriptor(\.positionUpdatedAt)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(Self.entry(from:))
    }

    public func markSynced(ids: [UUID]) async throws {
        try setState(ProgressJournalEntry.SyncState.synced, for: ids)
    }

    public func markFailed(ids: [UUID]) async throws {
        try setState(ProgressJournalEntry.SyncState.failed, for: ids, incrementAttempts: true)
    }

    public func latestPosition(forItemID itemID: String, episodeID: String?) async throws -> ProgressPosition? {
        try currentPosition(forItemID: itemID, episodeID: episodeID)
    }

    /// The most recent position per item, for restoring "Continue" offline.
    public func latestPositions(serverID: UUID, limit: Int = 50) async throws -> [ProgressPosition] {
        var descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.serverID == serverID },
            sortBy: [SortDescriptor(\.positionUpdatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit * 10
        var seen = Set<String>()
        var results: [ProgressPosition] = []
        for record in try modelContext.fetch(descriptor) {
            let key = "\(record.itemID)/\(record.episodeID ?? "")"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(Self.position(from: record))
            if results.count >= limit { break }
        }
        return results
    }

    /// Groups pending entries into the offline sessions ABS wants.
    ///
    /// One session per uninterrupted listen rather than one request per
    /// position: a two-hour offline listen is a few hundred journal entries
    /// and should be a handful of sessions.
    public func pendingSessions(limit: Int = 50) async throws -> [(sessionID: String, entries: [ProgressJournalEntry])] {
        let pending = try await pendingEntries(limit: limit * 50)
        var groups: [String: [ProgressJournalEntry]] = [:]
        var order: [String] = []
        for entry in pending where entry.origin == .local {
            let key = entry.sessionID ?? entry.id.uuidString
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.prefix(limit).compactMap { key in
            guard let entries = groups[key] else { return nil }
            return (key, entries)
        }
    }

    /// The days this device recorded listening on, for the streak.
    ///
    /// Only local entries count: a position that arrived from another device
    /// means someone listened, but not here, and a streak built from remote
    /// entries would count the same evening twice.
    public func listeningDays(serverID: UUID, since: Date) async throws -> [Date] {
        let local = ProgressJournalEntry.Origin.local.rawValue
        let descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate {
                $0.serverID == serverID && $0.originRaw == local && $0.positionUpdatedAt >= since
            },
            sortBy: [SortDescriptor(\.positionUpdatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).map(\.positionUpdatedAt)
    }

    /// Local entries for the statistics screen.
    public func entriesForStats(serverID: UUID, since: Date) async throws -> [ProgressJournalEntry] {
        let local = ProgressJournalEntry.Origin.local.rawValue
        let descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate {
                $0.serverID == serverID && $0.originRaw == local && $0.positionUpdatedAt >= since
            },
            sortBy: [SortDescriptor(\.positionUpdatedAt)]
        )
        return try modelContext.fetch(descriptor).map(Self.entry(from:))
    }

    /// Keeps the history useful without letting it grow without bound.
    public func prune(keepingPerItem keep: Int = 40) async throws {
        let all = try modelContext.fetch(
            FetchDescriptor<JournalEntryRecord>(sortBy: [SortDescriptor(\.positionUpdatedAt, order: .reverse)])
        )
        var counts: [String: Int] = [:]
        var removed = false
        for record in all {
            let key = "\(record.itemID)/\(record.episodeID ?? "")"
            counts[key, default: 0] += 1
            // Never drop something that has not reached the server.
            if counts[key]! > keep, record.syncStateRaw == ProgressJournalEntry.SyncState.synced.rawValue {
                modelContext.delete(record)
                removed = true
            }
        }
        if removed { try modelContext.save() }
    }

    // MARK: - Private

    /// Named apart from the async protocol method, which would otherwise
    /// shadow it and make every internal call an `await`.
    private func currentPosition(forItemID itemID: String, episodeID: String?) throws -> ProgressPosition? {
        var descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: Self.predicate(itemID: itemID, episodeID: episodeID),
            sortBy: [SortDescriptor(\.positionUpdatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(Self.position(from:))
    }

    private func setState(
        _ state: ProgressJournalEntry.SyncState,
        for ids: [UUID],
        incrementAttempts: Bool = false
    ) throws {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let records = try modelContext.fetch(
            FetchDescriptor<JournalEntryRecord>(predicate: #Predicate { idSet.contains($0.id) })
        )
        for record in records {
            record.syncStateRaw = state.rawValue
            if incrementAttempts { record.attemptCount += 1 }
        }
        try modelContext.save()
    }

    private static func predicate(itemID: String, episodeID: String?) -> Predicate<JournalEntryRecord> {
        if let episodeID {
            return #Predicate { $0.itemID == itemID && $0.episodeID == episodeID }
        }
        return #Predicate { $0.itemID == itemID && $0.episodeID == nil }
    }

    private static func record(from entry: ProgressJournalEntry) -> JournalEntryRecord {
        JournalEntryRecord(
            id: entry.id,
            serverID: entry.serverID,
            itemID: entry.position.itemID,
            episodeID: entry.position.episodeID,
            currentTime: entry.position.currentTime ?? 0,
            duration: entry.position.duration ?? 0,
            ebookLocation: entry.position.ebookLocation,
            ebookProgress: entry.position.ebookProgress,
            isFinished: entry.position.isFinished,
            positionUpdatedAt: entry.position.updatedAt,
            deviceID: entry.position.deviceID,
            deviceLabel: entry.position.deviceLabel,
            originRaw: entry.origin.rawValue,
            syncStateRaw: entry.syncState.rawValue,
            recordedAt: entry.recordedAt,
            attemptCount: entry.attemptCount,
            sessionID: entry.sessionID,
            timeListening: entry.timeListening
        )
    }

    private static func position(from record: JournalEntryRecord) -> ProgressPosition {
        ProgressPosition(
            itemID: record.itemID,
            episodeID: record.episodeID,
            currentTime: record.currentTime,
            duration: record.duration > 0 ? record.duration : nil,
            ebookLocation: record.ebookLocation,
            ebookProgress: record.ebookProgress,
            isFinished: record.isFinished,
            updatedAt: record.positionUpdatedAt,
            deviceID: record.deviceID,
            deviceLabel: record.deviceLabel
        )
    }

    private static func entry(from record: JournalEntryRecord) -> ProgressJournalEntry {
        ProgressJournalEntry(
            id: record.id,
            serverID: record.serverID,
            position: position(from: record),
            origin: ProgressJournalEntry.Origin(rawValue: record.originRaw) ?? .local,
            syncState: ProgressJournalEntry.SyncState(rawValue: record.syncStateRaw) ?? .pending,
            recordedAt: record.recordedAt,
            attemptCount: record.attemptCount,
            sessionID: record.sessionID,
            timeListening: record.timeListening
        )
    }
}
