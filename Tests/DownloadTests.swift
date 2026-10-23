import Foundation
import SwiftData
import Testing
@testable import DownloadKit
@testable import Persistence

private func candidate(
    _ id: String,
    series: String? = "Discworld",
    sequence: Double?,
    progress: Double = 0,
    finished: Bool = false,
    downloaded: Bool = false,
    finishedAt: Date? = nil
) -> SmartDownloadRules.Candidate {
    SmartDownloadRules.Candidate(
        itemID: id,
        seriesBaseName: series,
        seriesSequence: sequence,
        progressFraction: progress,
        isFinished: finished,
        isDownloaded: downloaded,
        finishedAt: finishedAt
    )
}

@Suite("Smart download rules")
struct SmartDownloadRulesTests {
    private var enabled: SmartDownloadRules {
        var rules = SmartDownloadRules.default
        rules.isAutoDownloadEnabled = true
        rules.isAutoRemoveEnabled = true
        return rules
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Nothing happens automatically until it is turned on")
    func offByDefault() {
        let rules = SmartDownloadRules.default
        #expect(!rules.isAutoDownloadEnabled)
        #expect(!rules.isAutoRemoveEnabled)
        // Wi-Fi only is the one that defaults on, per the spec.
        #expect(rules.wifiOnly)

        let candidates = [candidate("1", sequence: 1, progress: 0.9), candidate("2", sequence: 2)]
        #expect(rules.itemsToDownload(from: candidates).isEmpty)
    }

    @Test("The next book arrives once you are 80% through")
    func fetchesNextInSeries() {
        let candidates = [
            candidate("1", sequence: 1, progress: 0.85),
            candidate("2", sequence: 2),
            candidate("3", sequence: 3),
        ]
        // Only the next one — downloading a whole series unasked fills a phone.
        #expect(enabled.itemsToDownload(from: candidates) == ["2"])
    }

    @Test("Below the threshold, nothing is fetched")
    func respectsThreshold() {
        let candidates = [candidate("1", sequence: 1, progress: 0.5), candidate("2", sequence: 2)]
        #expect(enabled.itemsToDownload(from: candidates).isEmpty)
    }

    @Test("A book already on the device is not fetched again")
    func skipsDownloaded() {
        let candidates = [
            candidate("1", sequence: 1, progress: 0.9),
            candidate("2", sequence: 2, downloaded: true),
            candidate("3", sequence: 3),
        ]
        // The next *undownloaded* book, not a re-fetch and not a skip ahead.
        #expect(enabled.itemsToDownload(from: candidates) == ["3"])
    }

    @Test("Finishing a book also triggers the next one")
    func finishedTriggersNext() {
        let candidates = [candidate("1", sequence: 1, finished: true), candidate("2", sequence: 2)]
        #expect(enabled.itemsToDownload(from: candidates) == ["2"])
    }

    @Test("The end of a series fetches nothing")
    func endOfSeries() {
        let candidates = [candidate("1", sequence: 1, finished: true), candidate("2", sequence: 2, finished: true)]
        #expect(enabled.itemsToDownload(from: candidates).isEmpty)
    }

    @Test("A standalone book triggers nothing")
    func noSeries() {
        let candidates = [candidate("1", series: nil, sequence: nil, progress: 0.95)]
        #expect(enabled.itemsToDownload(from: candidates).isEmpty)
    }

    @Test("Each series is considered on its own")
    func multipleSeries() {
        let candidates = [
            candidate("a1", series: "A", sequence: 1, progress: 0.9),
            candidate("a2", series: "A", sequence: 2),
            candidate("b1", series: "B", sequence: 1, progress: 0.9),
            candidate("b2", series: "B", sequence: 2),
        ]
        #expect(enabled.itemsToDownload(from: candidates) == ["a2", "b2"])
    }

    @Test("Finished books are removed once they are old enough")
    func removesOldFinished() {
        let candidates = [
            candidate("old", sequence: 1, finished: true, downloaded: true,
                      finishedAt: now.addingTimeInterval(-10 * 86_400)),
            candidate("recent", sequence: 2, finished: true, downloaded: true,
                      finishedAt: now.addingTimeInterval(-2 * 86_400)),
        ]
        #expect(enabled.itemsToRemove(from: candidates, now: now) == ["old"])
    }

    @Test("An unfinished book is never removed, however old")
    func keepsUnfinished() {
        let candidates = [
            candidate("x", sequence: 1, progress: 0.3, downloaded: true,
                      finishedAt: now.addingTimeInterval(-100 * 86_400)),
        ]
        #expect(enabled.itemsToRemove(from: candidates, now: now).isEmpty)
    }

    @Test("Zero days means never remove")
    func zeroDaysNeverRemoves() {
        var rules = enabled
        rules.removeFinishedAfterDays = 0
        let candidates = [
            candidate("x", sequence: 1, finished: true, downloaded: true,
                      finishedAt: now.addingTimeInterval(-365 * 86_400)),
        ]
        #expect(rules.itemsToRemove(from: candidates, now: now).isEmpty)
    }

    @Test("Wi-Fi only blocks an expensive connection and nothing else")
    func wifiOnly() {
        var rules = SmartDownloadRules.default
        #expect(rules.allowsDownload(onExpensiveConnection: false))
        #expect(!rules.allowsDownload(onExpensiveConnection: true))

        rules.wifiOnly = false
        #expect(rules.allowsDownload(onExpensiveConnection: true))
    }

    @Test("Settings survive a round trip, since they live in defaults")
    func codable() throws {
        let data = try JSONEncoder().encode(enabled)
        let decoded = try JSONDecoder().decode(SmartDownloadRules.self, from: data)
        #expect(decoded == enabled)
    }
}

@Suite("Storage formatting")
struct StorageFormatterTests {
    @Test("Shows a size a person can act on")
    func formatting() {
        #expect(StorageFormatter.string(fromBytes: 0) == "—")
        let gigabyte = StorageFormatter.string(fromBytes: 2_000_000_000)
        #expect(gigabyte.contains("GB"))
        let megabyte = StorageFormatter.string(fromBytes: 50_000_000)
        #expect(megabyte.contains("MB"))
    }
}

@Suite("Download store")
struct DownloadStoreTests {
    private func makeStore() throws -> DownloadStore {
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
        return DownloadStore(modelContainer: container)
    }

    private let serverID = UUID()

    private var tracks: [(ino: String, index: Int, offset: Double, duration: Double, relativePath: String)] {
        [
            (ino: "100", index: 0, offset: 0, duration: 600, relativePath: "s/li-1/100.mp3"),
            (ino: "101", index: 1, offset: 600, duration: 900, relativePath: "s/li-1/101.mp3"),
        ]
    }

    @Test("A queued download is recorded with its files")
    func upsert() async throws {
        let store = try makeStore()
        try await store.upsert(
            serverID: serverID, itemID: "li-1", episodeID: nil,
            title: "The Hobbit", author: "Tolkien",
            tracks: tracks, expectedBytes: 1000, wasAutomatic: false
        )
        let summary = try await store.summary(serverID: serverID, itemID: "li-1", episodeID: nil)
        #expect(summary?.title == "The Hobbit")
        #expect(summary?.state == .queued)
    }

    @Test("An item is only downloaded once every file has landed")
    func completesOnLastFile() async throws {
        let store = try makeStore()
        try await store.upsert(
            serverID: serverID, itemID: "li-1", episodeID: nil,
            title: "Book", author: nil, tracks: tracks,
            expectedBytes: 1000, wasAutomatic: false
        )

        let firstDone = try await store.markFileComplete(
            serverID: serverID, itemID: "li-1", episodeID: nil, ino: "100", bytes: 400
        )
        #expect(!firstDone)

        let secondDone = try await store.markFileComplete(
            serverID: serverID, itemID: "li-1", episodeID: nil, ino: "101", bytes: 600
        )
        #expect(secondDone)

        let summary = try await store.summary(serverID: serverID, itemID: "li-1", episodeID: nil)
        #expect(summary?.state == .downloaded(bytes: 1000))
        #expect(summary?.bytesDownloaded == 1000)
    }

    @Test("A half-downloaded item offers no local tracks to play")
    func noPartialPlayback() async throws {
        let store = try makeStore()
        try await store.upsert(
            serverID: serverID, itemID: "li-1", episodeID: nil,
            title: "Book", author: nil, tracks: tracks,
            expectedBytes: 1000, wasAutomatic: false
        )
        _ = try await store.markFileComplete(
            serverID: serverID, itemID: "li-1", episodeID: nil, ino: "100", bytes: 400
        )
        // Half a book played offline would stop mid-sentence.
        #expect(try await store.localTracks(serverID: serverID, itemID: "li-1", episodeID: nil).isEmpty)
    }

    @Test("Re-queuing an existing download does not duplicate its files")
    func upsertIsIdempotent() async throws {
        let store = try makeStore()
        for _ in 0..<3 {
            try await store.upsert(
                serverID: serverID, itemID: "li-1", episodeID: nil,
                title: "Book", author: nil, tracks: tracks,
                expectedBytes: 1000, wasAutomatic: false
            )
        }
        _ = try await store.markFileComplete(
            serverID: serverID, itemID: "li-1", episodeID: nil, ino: "100", bytes: 400
        )
        let summary = try await store.summary(serverID: serverID, itemID: "li-1", episodeID: nil)
        // Two files, not six.
        #expect(summary?.bytesDownloaded == 400)
    }

    @Test("Removing a download takes its record with it")
    func remove() async throws {
        let store = try makeStore()
        try await store.upsert(
            serverID: serverID, itemID: "li-1", episodeID: nil,
            title: "Book", author: nil, tracks: tracks,
            expectedBytes: 1000, wasAutomatic: false
        )
        try await store.remove(serverID: serverID, itemID: "li-1", episodeID: nil)
        #expect(try await store.summary(serverID: serverID, itemID: "li-1", episodeID: nil) == nil)
    }

    @Test("Totals add up across items")
    func totals() async throws {
        let store = try makeStore()
        for id in ["li-1", "li-2"] {
            try await store.upsert(
                serverID: serverID, itemID: id, episodeID: nil,
                title: id, author: nil,
                tracks: [(ino: "1", index: 0, offset: 0, duration: 10, relativePath: "\(id)/1.mp3")],
                expectedBytes: 500, wasAutomatic: false
            )
            _ = try await store.markFileComplete(
                serverID: serverID, itemID: id, episodeID: nil, ino: "1", bytes: 500
            )
        }
        #expect(try await store.totalBytes(serverID: serverID) == 1000)
    }

    @Test("Two servers holding the same book are kept apart")
    func serversAreSeparate() async throws {
        let store = try makeStore()
        let other = UUID()
        try await store.upsert(
            serverID: serverID, itemID: "li-1", episodeID: nil, title: "Mine", author: nil,
            tracks: tracks, expectedBytes: 1, wasAutomatic: false
        )
        try await store.upsert(
            serverID: other, itemID: "li-1", episodeID: nil, title: "Theirs", author: nil,
            tracks: tracks, expectedBytes: 1, wasAutomatic: false
        )
        #expect(try await store.summary(serverID: serverID, itemID: "li-1", episodeID: nil)?.title == "Mine")
        #expect(try await store.summary(serverID: other, itemID: "li-1", episodeID: nil)?.title == "Theirs")
    }
}

@Suite("Download file naming")
struct DownloadNamingTests {
    @Test("Audio types map to the extension AVFoundation expects")
    func extensions() {
        #expect(BackgroundDownloadManager.fileExtension(for: "audio/mpeg") == "mp3")
        #expect(BackgroundDownloadManager.fileExtension(for: "audio/x-m4b") == "m4b")
        #expect(BackgroundDownloadManager.fileExtension(for: "audio/flac") == "flac")
        #expect(BackgroundDownloadManager.fileExtension(for: nil) == nil)
        #expect(BackgroundDownloadManager.fileExtension(for: "application/octet-stream") == nil)
    }
}
