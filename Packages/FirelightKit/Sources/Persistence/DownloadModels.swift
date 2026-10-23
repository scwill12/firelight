import Foundation
import SwiftData

/// One downloaded item, and the files that make it up.
///
/// Tracks the *book*, not individual files, because that is what a user
/// downloads, deletes and sees a size for. The per-file detail lives in
/// `files`, which is what playback needs to find a local track.
@Model
public final class DownloadRecord {
    @Attribute(.unique) public var compositeID: String
    public var serverID: UUID
    public var itemID: String
    public var episodeID: String?
    public var title: String
    public var author: String?

    /// `queued`, `downloading`, `paused`, `downloaded`, `failed`.
    public var stateRaw: String
    public var bytesDownloaded: Int64
    public var bytesExpected: Int64
    public var failureReason: String?

    public var requestedAt: Date
    public var completedAt: Date?
    /// Set when the user finished the book, so the tidy-up rule can find it.
    public var finishedAt: Date?
    /// True when Firelight downloaded this on its own rather than being asked.
    public var wasAutomatic: Bool

    @Relationship(deleteRule: .cascade, inverse: \DownloadedFile.download)
    public var files: [DownloadedFile] = []

    public init(
        serverID: UUID,
        itemID: String,
        episodeID: String? = nil,
        title: String,
        author: String? = nil,
        stateRaw: String = "queued",
        bytesDownloaded: Int64 = 0,
        bytesExpected: Int64 = 0,
        requestedAt: Date = .now,
        wasAutomatic: Bool = false
    ) {
        self.compositeID = "\(serverID.uuidString):\(itemID):\(episodeID ?? "")"
        self.serverID = serverID
        self.itemID = itemID
        self.episodeID = episodeID
        self.title = title
        self.author = author
        self.stateRaw = stateRaw
        self.bytesDownloaded = bytesDownloaded
        self.bytesExpected = bytesExpected
        self.requestedAt = requestedAt
        self.wasAutomatic = wasAutomatic
    }
}

/// One audio file on disk.
@Model
public final class DownloadedFile {
    /// The server's file id (`ino`), which is what `contentUrl` points at.
    public var ino: String
    public var trackIndex: Int
    public var startOffset: Double
    public var duration: Double
    /// Path relative to the downloads directory, so the record survives the
    /// container moving between app updates.
    public var relativePath: String
    public var bytes: Int64
    public var isComplete: Bool
    public var download: DownloadRecord?

    public init(
        ino: String,
        trackIndex: Int,
        startOffset: Double,
        duration: Double,
        relativePath: String,
        bytes: Int64 = 0,
        isComplete: Bool = false
    ) {
        self.ino = ino
        self.trackIndex = trackIndex
        self.startOffset = startOffset
        self.duration = duration
        self.relativePath = relativePath
        self.bytes = bytes
        self.isComplete = isComplete
    }
}
