import Foundation

/// A chapter. Verified against `Book.js`'s `ChapterObject` typedef: `id`,
/// `start`, `end` are numbers and `title` is a string. Seconds, not
/// milliseconds, and measured against the *book*, not a track.
public struct ABSChapter: Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let start: Double
    public let end: Double
    public let title: String?

    public init(id: Int, start: Double, end: Double, title: String?) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
    }

    public var duration: Double { max(0, end - start) }

    public func contains(_ time: Double) -> Bool {
        time >= start && time < end
    }
}

/// One audio file in a playback session.
///
/// Verified against `objects/files/AudioTrack.js`. A book is frequently many
/// tracks; `startOffset` is what turns a position inside one file into a
/// position in the book, and getting it wrong means every chapter mark is
/// wrong after the first file.
public struct ABSAudioTrack: Sendable, Hashable, Codable {
    public let index: Int?
    /// Where this track begins within the whole book, in seconds.
    public let startOffset: Double?
    public let duration: Double?
    public let title: String?
    /// A *relative* path: `/api/items/{itemId}/file/{ino}`, with no token.
    public let contentUrl: String?
    public let mimeType: String?
    public let codec: String?

    public var offset: Double { startOffset ?? 0 }
    public var length: Double { duration ?? 0 }

    public init(
        index: Int?,
        startOffset: Double?,
        duration: Double?,
        title: String?,
        contentUrl: String?,
        mimeType: String?,
        codec: String?
    ) {
        self.index = index
        self.startOffset = startOffset
        self.duration = duration
        self.title = title
        self.contentUrl = contentUrl
        self.mimeType = mimeType
        self.codec = codec
    }
}

/// The session ABS opens for a listen.
///
/// Verified against `objects/PlaybackSession.js` (`toJSONForClient`). Only the
/// fields Firelight uses are decoded; the rest (`deviceInfo`, `dayOfWeek`,
/// `mediaMetadata`) are server bookkeeping.
public struct ABSPlaybackSession: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let userId: String?
    public let libraryItemId: String?
    public let episodeId: String?
    public let mediaType: String?
    public let displayTitle: String?
    public let displayAuthor: String?
    public let coverPath: String?
    /// Total length of the book, in seconds.
    public let duration: Double?
    /// `direct` or `transcode`.
    public let playMethod: Int?
    /// Where the server thinks the listener is.
    public let currentTime: Double?
    public let startTime: Double?
    public let timeListening: Double?
    public let chapters: [ABSChapter]?
    public let audioTracks: [ABSAudioTrack]?
    public let startedAt: Date?
    public let updatedAt: Date?

    public var orderedTracks: [ABSAudioTrack] {
        (audioTracks ?? []).sorted { $0.offset < $1.offset }
    }

    public var orderedChapters: [ABSChapter] {
        (chapters ?? []).sorted { $0.start < $1.start }
    }

    /// Prefer the server's duration, but fall back to the tracks when it is
    /// missing — a book with no duration cannot be scrubbed.
    public var resolvedDuration: Double {
        if let duration, duration > 0 { return duration }
        return orderedTracks.reduce(0) { $0 + $1.length }
    }
}

/// What the client tells the server about itself when opening a session.
///
/// `forceDirectPlay` keeps ABS from transcoding when the device can play the
/// file as it is, which it can for everything Firelight supports.
public struct PlaybackSessionRequest: Sendable, Hashable, Codable {
    public var deviceInfo: DeviceInfo
    public var forceDirectPlay: Bool
    public var forceTranscode: Bool
    public var supportedMimeTypes: [String]
    public var mediaPlayer: String

    public struct DeviceInfo: Sendable, Hashable, Codable {
        public var deviceId: String
        public var clientName: String
        public var clientVersion: String
        public var manufacturer: String
        public var model: String
        public var sdkVersion: String?

        public init(
            deviceId: String,
            clientName: String = "Firelight",
            clientVersion: String,
            manufacturer: String = "Apple",
            model: String,
            sdkVersion: String? = nil
        ) {
            self.deviceId = deviceId
            self.clientName = clientName
            self.clientVersion = clientVersion
            self.manufacturer = manufacturer
            self.model = model
            self.sdkVersion = sdkVersion
        }
    }

    public init(
        deviceID: String,
        clientVersion: String,
        model: String,
        systemVersion: String?
    ) {
        self.deviceInfo = DeviceInfo(
            deviceId: deviceID,
            clientName: "Firelight",
            clientVersion: clientVersion,
            manufacturer: "Apple",
            model: model,
            sdkVersion: systemVersion
        )
        self.forceDirectPlay = true
        self.forceTranscode = false
        // What AVFoundation plays natively. Anything else, let ABS transcode.
        self.supportedMimeTypes = [
            "audio/mpeg", "audio/mp4", "audio/m4a", "audio/m4b", "audio/x-m4b",
            "audio/aac", "audio/flac", "audio/x-flac", "audio/wav", "audio/x-wav",
            "audio/aiff", "audio/x-aiff", "audio/opus", "audio/ogg",
        ]
        self.mediaPlayer = "AVPlayer"
    }
}

/// A position the user saved, with an optional note.
public struct ABSBookmark: Sendable, Hashable, Codable, Identifiable {
    public let libraryItemId: String?
    public let title: String?
    /// Seconds into the book.
    public let time: Double
    public let createdAt: Date?

    public var id: String { "\(libraryItemId ?? "")@\(Int(time))" }

    public init(libraryItemId: String?, title: String?, time: Double, createdAt: Date?) {
        self.libraryItemId = libraryItemId
        self.title = title
        self.time = time
        self.createdAt = createdAt
    }
}
