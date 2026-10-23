import Foundation
import SwiftData
import Testing
@testable import ABSKit
@testable import ABSMockServer
@testable import Persistence
@testable import SyncEngine

private func makeStore() throws -> SwiftDataJournalStore {
    let container = try ModelContainer(
        for: Schema(versionedSchema: CurrentSchema.self),
        configurations: ModelConfiguration(
            schema: Schema(versionedSchema: CurrentSchema.self),
            isStoredInMemoryOnly: true,
            // `.automatic` would switch CloudKit on, and CloudKit refuses
            // the cache models outright.
            cloudKitDatabase: .none
        )
    )
    return SwiftDataJournalStore(modelContainer: container)
}

private func entry(
    serverID: UUID,
    itemID: String = "li-1",
    seconds: TimeInterval,
    at updatedAt: Date,
    device: String = "iPhone",
    origin: ProgressJournalEntry.Origin = .local,
    sessionID: String? = nil,
    listening: TimeInterval = 0
) -> ProgressJournalEntry {
    ProgressJournalEntry(
        serverID: serverID,
        position: ProgressPosition(
            itemID: itemID,
            currentTime: seconds,
            duration: 36_000,
            updatedAt: updatedAt,
            deviceID: device.lowercased(),
            deviceLabel: device
        ),
        origin: origin,
        sessionID: sessionID,
        timeListening: listening
    )
}

@Suite("Progress journal store")
struct JournalStoreTests {
    private let serverID = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A position written is a position kept")
    func roundTrip() async throws {
        let store = try makeStore()
        try await store.append(entry(serverID: serverID, seconds: 1200, at: now))

        let position = try await store.latestPosition(forItemID: "li-1", episodeID: nil)
        #expect(position?.currentTime == 1200)
        #expect(position?.deviceLabel == "iPhone")
    }

    @Test("The latest position is the newest by position time, not write order")
    func latestWins() async throws {
        let store = try makeStore()
        // Written second, but reached earlier.
        try await store.append(entry(serverID: serverID, seconds: 1800, at: now))
        try await store.append(entry(serverID: serverID, seconds: 900, at: now.addingTimeInterval(-600)))

        let position = try await store.latestPosition(forItemID: "li-1", episodeID: nil)
        #expect(position?.currentTime == 1800)
    }

    @Test("Everything written starts pending")
    func pendingByDefault() async throws {
        let store = try makeStore()
        try await store.append(entry(serverID: serverID, seconds: 100, at: now))
        try await store.append(entry(serverID: serverID, seconds: 200, at: now.addingTimeInterval(10)))
        #expect(try await store.pendingEntries(limit: 10).count == 2)
    }

    @Test("Marking synced takes entries out of the queue but not out of history")
    func markSynced() async throws {
        let store = try makeStore()
        let first = entry(serverID: serverID, seconds: 100, at: now)
        try await store.append(first)
        try await store.markSynced(ids: [first.id])

        #expect(try await store.pendingEntries(limit: 10).isEmpty)
        #expect(try await store.entries(forItemID: "li-1", episodeID: nil, limit: 10).count == 1)
    }

    @Test("A failed send is counted, not dropped")
    func markFailed() async throws {
        let store = try makeStore()
        let only = entry(serverID: serverID, seconds: 100, at: now)
        try await store.append(only)
        try await store.markFailed(ids: [only.id])

        let history = try await store.entries(forItemID: "li-1", episodeID: nil, limit: 10)
        #expect(history.first?.syncState == .failed)
        #expect(history.first?.attemptCount == 1)
    }

    @Test("Episode progress is kept apart from the item's own")
    func episodesAreSeparate() async throws {
        let store = try makeStore()
        try await store.append(entry(serverID: serverID, seconds: 100, at: now))

        var episodeEntry = entry(serverID: serverID, seconds: 900, at: now)
        episodeEntry.position.episodeID = "ep-1"
        try await store.append(episodeEntry)

        #expect(try await store.latestPosition(forItemID: "li-1", episodeID: nil)?.currentTime == 100)
        #expect(try await store.latestPosition(forItemID: "li-1", episodeID: "ep-1")?.currentTime == 900)
    }

    @Test("A remote position far from the local one asks rather than jumping")
    func appendAndResolveAsks() async throws {
        let store = try makeStore()
        try await store.append(entry(serverID: serverID, seconds: 12_005, at: now))

        let remote = entry(
            serverID: serverID,
            seconds: 13_330,
            at: now.addingTimeInterval(120),
            device: "iPad",
            origin: .remote
        )
        let outcome = try await store.appendAndResolve(remote, resolver: ProgressConflictResolver())

        guard case .ask = outcome else {
            Issue.record("Expected a prompt, got \(outcome)")
            return
        }
    }

    @Test("A nearby remote position is adopted silently")
    func appendAndResolveTakesRemote() async throws {
        let store = try makeStore()
        try await store.append(entry(serverID: serverID, seconds: 1200, at: now))

        let remote = entry(
            serverID: serverID,
            seconds: 1230,
            at: now.addingTimeInterval(60),
            device: "iPad",
            origin: .remote
        )
        #expect(try await store.appendAndResolve(remote, resolver: ProgressConflictResolver()) == .takeRemote)
    }

    @Test("This device's own writes never conflict with themselves")
    func localNeverConflicts() async throws {
        let store = try makeStore()
        try await store.append(entry(serverID: serverID, seconds: 100, at: now))

        let localJump = entry(serverID: serverID, seconds: 9000, at: now.addingTimeInterval(10))
        #expect(try await store.appendAndResolve(localJump, resolver: ProgressConflictResolver()) == .noChange)
    }

    @Test("Offline entries group into one session, not hundreds")
    func pendingSessionsGrouping() async throws {
        let store = try makeStore()
        let sessionA = "session-a"
        let sessionB = "session-b"
        for second in stride(from: 0, to: 100, by: 10) {
            try await store.append(entry(
                serverID: serverID,
                seconds: Double(second),
                at: now.addingTimeInterval(Double(second)),
                sessionID: sessionA,
                listening: Double(second)
            ))
        }
        try await store.append(entry(
            serverID: serverID, seconds: 500, at: now.addingTimeInterval(500), sessionID: sessionB
        ))

        let sessions = try await store.pendingSessions()
        #expect(sessions.count == 2)
        #expect(sessions.first { $0.sessionID == sessionA }?.entries.count == 10)
    }

    @Test("Pruning never discards something the server has not seen")
    func pruneKeepsUnsynced() async throws {
        let store = try makeStore()
        for index in 0..<60 {
            try await store.append(entry(
                serverID: serverID,
                seconds: Double(index),
                at: now.addingTimeInterval(Double(index))
            ))
        }
        try await store.prune(keepingPerItem: 10)

        // All 60 are pending, so none may be dropped.
        #expect(try await store.entries(forItemID: "li-1", episodeID: nil, limit: 100).count == 60)
    }

    @Test("Pruning trims synced history once it is long enough")
    func pruneTrimsSynced() async throws {
        let store = try makeStore()
        var ids: [UUID] = []
        for index in 0..<60 {
            let record = entry(
                serverID: serverID,
                seconds: Double(index),
                at: now.addingTimeInterval(Double(index))
            )
            ids.append(record.id)
            try await store.append(record)
        }
        try await store.markSynced(ids: ids)
        try await store.prune(keepingPerItem: 10)

        #expect(try await store.entries(forItemID: "li-1", episodeID: nil, limit: 100).count == 10)
    }
}

@Suite("Offline session building")
struct LocalSessionTests {
    private let serverID = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A run of entries becomes one session spanning first to last")
    func sessionSpansTheRun() {
        let entries = [
            entry(serverID: serverID, seconds: 100, at: now, sessionID: "s1", listening: 0),
            entry(serverID: serverID, seconds: 400, at: now.addingTimeInterval(300), sessionID: "s1", listening: 300),
            entry(serverID: serverID, seconds: 700, at: now.addingTimeInterval(600), sessionID: "s1", listening: 600),
        ]
        let session = ProgressSyncService.localSession(
            from: entries,
            device: DeviceIdentity(id: "device-1", label: "iPhone")
        )

        #expect(session.id == "s1")
        #expect(session.startTime == 100)
        #expect(session.currentTime == 700)
        // The running total, not a delta — ABS reads `timeListening` here.
        #expect(session.timeListening == 600)
        #expect(session.startedAt == now)
        #expect(session.updatedAt == now.addingTimeInterval(600))
    }

    @Test("The session id is ours, so ABS does not replace it")
    func idIsNotPlayLocal() {
        let session = ProgressSyncService.localSession(
            from: [entry(serverID: serverID, seconds: 10, at: now)],
            device: DeviceIdentity(id: "d", label: "iPhone")
        )
        // ABS replaces any id starting with `play_local_`; a UUID survives, so
        // topping the same session up later works.
        #expect(!session.id.hasPrefix("play_local_"))
    }

    @Test("Encodes with the key names ABS reads")
    func encodingKeys() throws {
        let session = ProgressSyncService.localSession(
            from: [entry(serverID: serverID, seconds: 10, at: now, listening: 5)],
            device: DeviceIdentity(id: "d", label: "iPhone")
        )
        let data = try ABSJSON.encoder.encode(session)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["libraryItemId"] as? String == "li-1")
        #expect(json["timeListening"] != nil)
        #expect(json["currentTime"] != nil)
        #expect(json["deviceInfo"] != nil)
        // `timeListened` is the in-session delta and must not appear here.
        #expect(json["timeListened"] == nil)
    }
}

@Suite("Progress endpoints")
struct ProgressEndpointTests {
    @Test("The episode id goes in the path, not the body")
    func episodeInPath() throws {
        let request = try ABSEndpoint.updateProgress(
            itemID: "li-1", episodeID: "ep-2", currentTime: 100, duration: 200,
            progress: 0.5, isFinished: false, ebookLocation: nil, ebookProgress: nil
        )
        #expect(request.path == "/api/me/progress/li-1/ep-2")
        #expect(request.method == .patch)

        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["episodeId"] == nil)
        #expect(json["currentTime"] as? Double == 100)
    }

    @Test("A book has no episode segment")
    func bookPath() throws {
        let request = try ABSEndpoint.updateProgress(
            itemID: "li-1", episodeID: nil, currentTime: 1, duration: 2,
            progress: 0.5, isFinished: nil, ebookLocation: nil, ebookProgress: nil
        )
        #expect(request.path == "/api/me/progress/li-1")
    }

    @Test("Ebook position travels as a locator and a percentage")
    func ebookProgress() throws {
        let request = try ABSEndpoint.updateProgress(
            itemID: "li-1", episodeID: nil, currentTime: nil, duration: nil,
            progress: nil, isFinished: nil,
            ebookLocation: #"{"href":"ch3.xhtml"}"#, ebookProgress: 0.42
        )
        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["ebookProgress"] as? Double == 0.42)
        #expect((json["ebookLocation"] as? String)?.contains("ch3") == true)
    }
}

@Suite("Socket payload decoding")
struct SocketDecodingTests {
    @Test("Decodes a bare progress payload")
    func bare() throws {
        let payload: [String: Any] = [
            "id": "mp-1", "libraryItemId": "li-1", "currentTime": 900.0,
            "duration": 3600.0, "progress": 0.25, "isFinished": false,
            "lastUpdate": 1_700_000_000_000,
        ]
        let progress = try #require(ABSSocketClient.decodeProgress(from: [payload]))
        #expect(progress.libraryItemId == "li-1")
        #expect(progress.currentTime == 900)
    }

    @Test("Decodes a payload wrapped in a data envelope")
    func wrapped() throws {
        let inner: [String: Any] = ["id": "mp-1", "libraryItemId": "li-2", "currentTime": 10.0]
        let progress = try #require(ABSSocketClient.decodeProgress(from: [["data": inner]]))
        #expect(progress.libraryItemId == "li-2")
    }

    @Test("Nonsense is ignored rather than crashing the socket")
    func rubbish() {
        #expect(ABSSocketClient.decodeProgress(from: []) == nil)
        #expect(ABSSocketClient.decodeProgress(from: ["hello"]) == nil)
    }
}
