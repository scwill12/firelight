import Foundation

/// What the demo library contains, and the Audiobookshelf-shaped JSON for it.
///
/// The JSON is written out by hand rather than encoded from `ABSKit`'s models,
/// because those models have no public initialiser — they exist to be decoded,
/// not built. Hand-written payloads drift, so `DemoCatalogueTests` decodes
/// every one of them with the app's real decoder. If a field changes shape,
/// that test fails rather than the demo quietly emptying itself.
public enum DemoCatalogue {
    public static let libraryID = "demo-library"

    public struct Book: Sendable {
        public let id: String
        public let title: String
        public let author: String
        public let narrator: String?
        public let coverResource: String
        /// Audio chapters, in order. Empty for a book with no audio.
        public let tracks: [Track]
        /// The bundled ebook or comic, if there is one.
        public let fileResource: String?
        public let fileExtension: String?
    }

    public struct Track: Sendable {
        public let resource: String
        public let title: String
        public let duration: TimeInterval
        public let offset: TimeInterval
    }

    /// Durations are the real ones, measured when the audio was synthesised.
    /// A wrong duration here would put every chapter mark in the wrong place.
    public static let aliceTracks: [Track] = {
        let measured: [(String, String, TimeInterval)] = [
            ("alice-1", "Down the Rabbit-Hole", 31.831),
            ("alice-2", "The Pool of Tears", 17.494),
            ("alice-3", "A Caucus-Race", 14.081),
        ]
        var offset: TimeInterval = 0
        return measured.map { resource, title, duration in
            defer { offset += duration }
            return Track(resource: resource, title: title, duration: duration, offset: offset)
        }
    }()

    public static let books: [Book] = [
        Book(
            id: "demo-alice-audio",
            title: "Alice's Adventures in Wonderland",
            author: "Lewis Carroll",
            narrator: "A synthesised voice",
            coverResource: "cover-alice",
            tracks: aliceTracks,
            fileResource: nil,
            fileExtension: nil
        ),
        Book(
            id: "demo-alice-ebook",
            title: "Alice's Adventures in Wonderland",
            author: "Lewis Carroll",
            narrator: nil,
            coverResource: "cover-alice-ebook",
            tracks: [],
            fileResource: "alice",
            fileExtension: "epub"
        ),
        Book(
            id: "demo-comic",
            title: "A Sample Comic",
            author: "Firelight",
            narrator: nil,
            coverResource: "cover-comic",
            tracks: [],
            fileResource: "sample",
            fileExtension: "cbz"
        ),
    ]

    public static func book(id: String) -> Book? {
        books.first { $0.id == id }
    }

    public static var totalDuration: TimeInterval {
        aliceTracks.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Payloads

    /// Epoch milliseconds, which is what ABS sends and what the decoder reads.
    private static let addedAt = Date(timeIntervalSince1970: 1_735_689_600).timeIntervalSince1970 * 1000

    public static var statusJSON: String {
        """
        {"app":"audiobookshelf","serverVersion":"2.37.1","isInit":true,\
        "language":"en-us","authMethods":["local"]}
        """
    }

    public static func loginJSON(accessToken: String, refreshToken: String) -> String {
        """
        {"user":{"id":"demo-user","username":"\(DemoMode.username)","type":"user",\
        "token":"\(accessToken)","accessToken":"\(accessToken)",\
        "refreshToken":"\(refreshToken)","mediaProgress":[],"bookmarks":[],\
        "isActive":true,"permissions":{"download":true,"update":false,"delete":false,\
        "upload":false,"accessAllLibraries":true,"accessAllTags":true,\
        "accessExplicitContent":true}},\
        "userDefaultLibraryId":"\(libraryID)","Source":"demo"}
        """
    }

    public static var meJSON: String {
        """
        {"id":"demo-user","username":"\(DemoMode.username)","type":"user",\
        "mediaProgress":[],"bookmarks":[],"isActive":true,\
        "permissions":{"download":true,"update":false,"delete":false,"upload":false,\
        "accessAllLibraries":true,"accessAllTags":true,"accessExplicitContent":true}}
        """
    }

    public static var librariesJSON: String {
        """
        {"libraries":[{"id":"\(libraryID)","name":"Demo library",\
        "mediaType":"book","provider":"google","displayOrder":1}]}
        """
    }

    public static var libraryItemsJSON: String {
        let entries = books.map(itemJSON).joined(separator: ",")
        return """
        {"results":[\(entries)],"total":\(books.count),"limit":0,"page":0,\
        "sortDesc":false,"mediaType":"book","minified":true,"collapseseries":false}
        """
    }

    public static func itemJSON(_ book: Book) -> String {
        let duration = book.tracks.reduce(0) { $0 + $1.duration }
        let chapters = book.tracks.enumerated().map { index, track in
            """
            {"id":\(index),"start":\(track.offset),\
            "end":\(track.offset + track.duration),"title":"\(escaped(track.title))"}
            """
        }.joined(separator: ",")

        let audioFiles = book.tracks.enumerated().map { index, track in
            """
            {"index":\(index + 1),"ino":"\(track.resource)",\
            "duration":\(track.duration),"metadata":{"filename":"\(track.resource).m4a"}}
            """
        }.joined(separator: ",")

        let ebookFile = book.fileExtension.map {
            """
            ,"ebookFile":{"ino":"\(book.fileResource ?? "")","ebookFormat":"\($0)",\
            "metadata":{"filename":"\(book.fileResource ?? "").\($0)"}}
            """
        } ?? ""

        return """
        {"id":"\(book.id)","libraryId":"\(libraryID)","mediaType":"book",\
        "addedAt":\(addedAt),"updatedAt":\(addedAt),"isMissing":false,"isInvalid":false,\
        "numFiles":\(max(book.tracks.count, 1)),"size":0,\
        "media":{"id":"\(book.id)-media","coverPath":"/demo/\(book.coverResource).png",\
        "duration":\(duration),"numTracks":\(book.tracks.count),\
        "metadata":{"title":"\(escaped(book.title))","titleIgnorePrefix":"\(escaped(book.title))",\
        "subtitle":"","authorName":"\(escaped(book.author))",\
        "narratorName":"\(escaped(book.narrator ?? ""))","seriesName":"","publishedYear":"1865",\
        "description":"A short public-domain excerpt, bundled so Firelight has something to show before you connect your own server.",\
        "genres":["Classics"],"explicit":false,"language":"English"},\
        "chapters":[\(chapters)],"audioFiles":[\(audioFiles)],"numAudioFiles":\(book.tracks.count)\(ebookFile)}}
        """
    }

    public static func playJSON(_ book: Book, sessionID: String) -> String {
        let tracks = book.tracks.enumerated().map { index, track in
            """
            {"index":\(index + 1),"startOffset":\(track.offset),\
            "duration":\(track.duration),"title":"\(escaped(track.title))",\
            "contentUrl":"/api/items/\(book.id)/file/\(track.resource)",\
            "mimeType":"audio/mp4","codec":"aac","metadata":{"filename":"\(track.resource).m4a"}}
            """
        }.joined(separator: ",")

        let chapters = book.tracks.enumerated().map { index, track in
            """
            {"id":\(index),"start":\(track.offset),\
            "end":\(track.offset + track.duration),"title":"\(escaped(track.title))"}
            """
        }.joined(separator: ",")

        let duration = book.tracks.reduce(0) { $0 + $1.duration }
        return """
        {"id":"\(sessionID)","libraryItemId":"\(book.id)","episodeId":null,\
        "displayTitle":"\(escaped(book.title))","displayAuthor":"\(escaped(book.author))",\
        "coverPath":"/demo/\(book.coverResource).png","duration":\(duration),\
        "playMethod":0,"currentTime":0,"startTime":0,"timeListening":0,\
        "startedAt":\(addedAt),"updatedAt":\(addedAt),\
        "chapters":[\(chapters)],"audioTracks":[\(tracks)]}
        """
    }

    /// Quotation marks are the only character these strings can contain that
    /// would break the JSON; everything else here is ours and plain.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
