import Foundation

/// A folder inside a library — the destination an upload has to name.
public struct ABSFolder: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let fullPath: String?
    public let libraryId: String?
}

/// A library with its folders, which `GET /api/libraries` includes.
public struct ABSLibraryWithFolders: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let mediaType: String?
    public let folders: [ABSFolder]?

    public var isPodcast: Bool { mediaType == "podcast" }
}

public struct ABSLibrariesWithFoldersResponse: Sendable, Codable {
    public let libraries: [ABSLibraryWithFolders]
}

/// A background job, for showing scan progress.
public struct ABSTask: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let action: String?
    public let title: String?
    public let description: String?
    public let isFailed: Bool?
    public let isFinished: Bool?
    public let error: String?
}

public struct ABSTasksResponse: Sendable, Codable {
    public let tasks: [ABSTask]
}

/// A user, for the admin screen.
public struct ABSAdminUser: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let username: String
    public let type: String?
    public let isActive: Bool?
    public let lastSeen: Date?
    public let createdAt: Date?

    public var isAdmin: Bool { type == "admin" || type == "root" }
}

public struct ABSUsersResponse: Sendable, Codable {
    public let users: [ABSAdminUser]
}

/// An open listening session, for the admin screen.
public struct ABSListeningSession: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let userId: String?
    public let displayTitle: String?
    public let displayAuthor: String?
    public let mediaPlayer: String?
    public let currentTime: Double?
    public let updatedAt: Date?
}

public struct ABSSessionsResponse: Sendable, Codable {
    public let sessions: [ABSListeningSession]?
    public let total: Int?
}

/// What an upload needs.
///
/// Verified against `MiscController.handleUpload`: the body fields are
/// `library`, `folder` and `title` (all required), plus optional `author` and
/// `series`. The server builds the destination path from author/series/title,
/// so those are not cosmetic — they decide where the file lands on disk.
public struct UploadRequest: Sendable, Hashable {
    public let libraryID: String
    public let folderID: String
    public let title: String
    public let author: String?
    public let series: String?
    public let files: [UploadFile]

    public init(
        libraryID: String,
        folderID: String,
        title: String,
        author: String? = nil,
        series: String? = nil,
        files: [UploadFile]
    ) {
        self.libraryID = libraryID
        self.folderID = folderID
        self.title = title
        self.author = author
        self.series = series
        self.files = files
    }
}

public struct UploadFile: Sendable, Hashable {
    public let filename: String
    public let mimeType: String
    public let data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    /// A reasonable guess from the extension; ABS does not check it.
    public static func mimeType(forFilename name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "mp3": "audio/mpeg"
        case "m4a": "audio/mp4"
        case "m4b": "audio/x-m4b"
        case "flac": "audio/flac"
        case "opus", "ogg": "audio/ogg"
        case "epub": "application/epub+zip"
        case "pdf": "application/pdf"
        case "cbz": "application/vnd.comicbook+zip"
        case "cbr": "application/vnd.comicbook-rar"
        case "mobi", "azw3": "application/x-mobipocket-ebook"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        default: "application/octet-stream"
        }
    }
}

/// Builds the multipart body an upload needs.
///
/// Separated from the client so the boundary handling can be tested without a
/// server — a malformed multipart body fails in ways that are very hard to
/// read from the other end.
public enum MultipartBody {
    public static func make(boundary: String, request: UploadRequest) -> Data {
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        // The names ABS reads: `library` and `folder`, not `libraryId`.
        field("library", request.libraryID)
        field("folder", request.folderID)
        field("title", request.title)
        if let author = request.author, !author.isEmpty { field("author", author) }
        if let series = request.series, !series.isEmpty { field("series", series) }

        for (index, file) in request.files.enumerated() {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data(
                "Content-Disposition: form-data; name=\"file\(index)\"; filename=\"\(file.filename)\"\r\n".utf8
            ))
            body.append(Data("Content-Type: \(file.mimeType)\r\n\r\n".utf8))
            body.append(file.data)
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    public static func newBoundary() -> String {
        "Firelight-\(UUID().uuidString)"
    }
}
