import ABSKit
import Foundation
import Persistence
import SwiftData

/// A download as the UI sees it.
public struct DownloadSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let serverID: UUID
    public let itemID: String
    public let episodeID: String?
    public let title: String
    public let author: String?
    public let state: DownloadState
    public let bytesDownloaded: Int64
    public let bytesExpected: Int64
    public let completedAt: Date?
    public let wasAutomatic: Bool

    public var fraction: Double {
        guard bytesExpected > 0 else { return 0 }
        return min(max(Double(bytesDownloaded) / Double(bytesExpected), 0), 1)
    }
}

/// One downloaded file, for playback.
public struct DownloadedTrack: Sendable, Hashable {
    public let ino: String
    public let trackIndex: Int
    public let startOffset: Double
    public let duration: Double
    public let url: URL
}

/// Reads and writes download records.
@ModelActor
public actor DownloadStore {
    public func upsert(
        serverID: UUID,
        itemID: String,
        episodeID: String?,
        title: String,
        author: String?,
        tracks: [(ino: String, index: Int, offset: Double, duration: Double, relativePath: String)],
        expectedBytes: Int64,
        wasAutomatic: Bool
    ) throws {
        let composite = "\(serverID.uuidString):\(itemID):\(episodeID ?? "")"
        let existing = try modelContext.fetch(
            FetchDescriptor<DownloadRecord>(predicate: #Predicate { $0.compositeID == composite })
        ).first

        let record: DownloadRecord
        if let existing {
            record = existing
            record.stateRaw = "queued"
            record.failureReason = nil
        } else {
            record = DownloadRecord(
                serverID: serverID,
                itemID: itemID,
                episodeID: episodeID,
                title: title,
                author: author,
                bytesExpected: expectedBytes,
                wasAutomatic: wasAutomatic
            )
            modelContext.insert(record)
        }
        record.bytesExpected = expectedBytes

        let knownInos = Set(record.files.map(\.ino))
        for track in tracks where !knownInos.contains(track.ino) {
            let file = DownloadedFile(
                ino: track.ino,
                trackIndex: track.index,
                startOffset: track.offset,
                duration: track.duration,
                relativePath: track.relativePath
            )
            file.download = record
            modelContext.insert(file)
        }
        try modelContext.save()
    }

    public func setState(serverID: UUID, itemID: String, episodeID: String?, state: DownloadState) throws {
        guard let record = try record(serverID: serverID, itemID: itemID, episodeID: episodeID) else { return }
        switch state {
        case .notDownloaded: record.stateRaw = "notDownloaded"
        case .queued: record.stateRaw = "queued"
        case .downloading: record.stateRaw = "downloading"
        case .paused: record.stateRaw = "paused"
        case .downloaded(let bytes):
            record.stateRaw = "downloaded"
            record.bytesDownloaded = bytes
            record.completedAt = .now
        case .failed(let reason):
            record.stateRaw = "failed"
            record.failureReason = reason
        }
        try modelContext.save()
    }

    public func markFileComplete(
        serverID: UUID,
        itemID: String,
        episodeID: String?,
        ino: String,
        bytes: Int64
    ) throws -> Bool {
        guard let record = try record(serverID: serverID, itemID: itemID, episodeID: episodeID) else { return false }
        guard let file = record.files.first(where: { $0.ino == ino }) else { return false }
        file.isComplete = true
        file.bytes = bytes
        record.bytesDownloaded = record.files.reduce(0) { $0 + $1.bytes }

        let allDone = record.files.allSatisfy(\.isComplete)
        if allDone {
            record.stateRaw = "downloaded"
            record.completedAt = .now
        } else {
            record.stateRaw = "downloading"
        }
        try modelContext.save()
        return allDone
    }

    public func summaries(serverID: UUID) throws -> [DownloadSummary] {
        try modelContext.fetch(
            FetchDescriptor<DownloadRecord>(
                predicate: #Predicate { $0.serverID == serverID },
                sortBy: [SortDescriptor(\.requestedAt, order: .reverse)]
            )
        ).map(Self.summary(from:))
    }

    public func summary(serverID: UUID, itemID: String, episodeID: String?) throws -> DownloadSummary? {
        try record(serverID: serverID, itemID: itemID, episodeID: episodeID).map(Self.summary(from:))
    }

    /// The local files for an item, if it is fully downloaded.
    public func localTracks(serverID: UUID, itemID: String, episodeID: String?) throws -> [DownloadedTrack] {
        guard let record = try record(serverID: serverID, itemID: itemID, episodeID: episodeID),
              record.stateRaw == "downloaded",
              let root = try? AppGroup.downloadsURL()
        else { return [] }

        return record.files
            .filter(\.isComplete)
            .sorted { $0.trackIndex < $1.trackIndex }
            .map {
                DownloadedTrack(
                    ino: $0.ino,
                    trackIndex: $0.trackIndex,
                    startOffset: $0.startOffset,
                    duration: $0.duration,
                    url: root.appending(path: $0.relativePath)
                )
            }
    }

    public func totalBytes(serverID: UUID) throws -> Int64 {
        try summaries(serverID: serverID).reduce(0) { $0 + $1.bytesDownloaded }
    }

    /// Deletes the record and the files on disk.
    public func remove(serverID: UUID, itemID: String, episodeID: String?) throws {
        guard let record = try record(serverID: serverID, itemID: itemID, episodeID: episodeID) else { return }
        if let root = try? AppGroup.downloadsURL() {
            for file in record.files {
                try? FileManager.default.removeItem(at: root.appending(path: file.relativePath))
            }
        }
        modelContext.delete(record)
        try modelContext.save()
    }

    /// Records whose item the user has finished, for the tidy-up rule.
    public func markFinished(serverID: UUID, itemID: String, at date: Date = .now) throws {
        guard let record = try record(serverID: serverID, itemID: itemID, episodeID: nil) else { return }
        record.finishedAt = date
        try modelContext.save()
    }

    public func finishedAt(serverID: UUID, itemID: String) throws -> Date? {
        try record(serverID: serverID, itemID: itemID, episodeID: nil)?.finishedAt
    }

    // MARK: - Private

    private func record(serverID: UUID, itemID: String, episodeID: String?) throws -> DownloadRecord? {
        let composite = "\(serverID.uuidString):\(itemID):\(episodeID ?? "")"
        return try modelContext.fetch(
            FetchDescriptor<DownloadRecord>(predicate: #Predicate { $0.compositeID == composite })
        ).first
    }

    private static func summary(from record: DownloadRecord) -> DownloadSummary {
        let state: DownloadState = switch record.stateRaw {
        case "downloaded": .downloaded(bytes: record.bytesDownloaded)
        case "downloading": .downloading(fraction: Self.fraction(record))
        case "paused": .paused(fraction: Self.fraction(record))
        case "queued": .queued
        case "failed": .failed(reason: record.failureReason ?? "Download failed")
        default: .notDownloaded
        }
        return DownloadSummary(
            id: record.compositeID,
            serverID: record.serverID,
            itemID: record.itemID,
            episodeID: record.episodeID,
            title: record.title,
            author: record.author,
            state: state,
            bytesDownloaded: record.bytesDownloaded,
            bytesExpected: record.bytesExpected,
            completedAt: record.completedAt,
            wasAutomatic: record.wasAutomatic
        )
    }

    private static func fraction(_ record: DownloadRecord) -> Double {
        guard record.bytesExpected > 0 else { return 0 }
        return min(max(Double(record.bytesDownloaded) / Double(record.bytesExpected), 0), 1)
    }
}
