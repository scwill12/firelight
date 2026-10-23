import Foundation

/// What the demo library contains, and the Audiobookshelf-shaped JSON for it.
///
/// The contents come from `demo-library.json`, written by
/// `scripts/make_demo_library.py` when it generates the audio. That matters
/// for one field above all: a track's **duration is measured**, not guessed,
/// and a wrong one puts every chapter mark after it in the wrong place. Had
/// the durations been copied into Swift by hand they would drift the first
/// time anyone re-ran the script.
///
/// The ABS payloads below are still written by hand, because `ABSKit`'s
/// models have no public initialiser — they exist to be decoded, not built.
/// Hand-written payloads drift too, so `DemoLibraryTests` decodes every one
/// with the app's real decoder.
public enum DemoCatalogue {
    public static let libraryID = "demo-library"

    public struct Book: Sendable, Codable {
        public let id: String
        public let title: String
        public let author: String
        public let year: String
        public let blurb: String
        /// Resource name of the cover PNG.
        public let cover: String
        public let narrator: String?
        public let tracks: [Track]
        public let file: File?

        public struct File: Sendable, Codable {
            public let resource: String
            public let ext: String
        }
    }

    public struct Track: Sendable, Codable {
        public let resource: String
        public let title: String
        public let duration: TimeInterval
        /// Where this track starts in book time.
        public let offset: TimeInterval
    }

    /// Decoded once. An empty library would be a build mistake — the manifest
    /// ships in the bundle — so it is worth being loud about in a debug build
    /// rather than quietly showing a reviewer nothing.
    public static let books: [Book] = {
        guard let data = DemoBundle.data(named: "demo-library", extension: "json") else {
            assertionFailure("demo-library.json is missing from DemoKit's resources.")
            return []
        }
        do {
            return try JSONDecoder().decode([Book].self, from: data)
        } catch {
            assertionFailure("demo-library.json did not decode: \(error)")
            return []
        }
    }()

    public static func book(id: String) -> Book? {
        books.first { $0.id == id }
    }

    // MARK: - Payloads

    /// Epoch milliseconds, which is what ABS sends and what the decoder reads.
    private static let newestAddedAt = 1_735_689_600_000.0

    /// Each book is "added" a day before the one in front of it.
    ///
    /// A library where everything arrived in the same millisecond sorts
    /// alphabetically under any date order, which makes "Recently added" a
    /// lie and reads as generated — because it is. Staggering costs nothing
    /// and gives the shelves something true to sort on.
    private static func addedAt(_ book: Book) -> Double {
        let index = books.firstIndex { $0.id == book.id } ?? 0
        let day = 86_400_000.0
        return newestAddedAt - Double(index) * day
    }

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
        let chapters = chaptersJSON(book)

        let audioFiles = book.tracks.enumerated().map { index, track in
            """
            {"index":\(index + 1),"ino":"\(track.resource)",\
            "duration":\(track.duration),"metadata":{"filename":"\(track.resource).m4a"}}
            """
        }.joined(separator: ",")

        let ebookFile = book.file.map {
            """
            ,"ebookFile":{"ino":"\($0.resource)","ebookFormat":"\($0.ext)",\
            "metadata":{"filename":"\($0.resource).\($0.ext)"}}
            """
        } ?? ""

        return """
        {"id":"\(book.id)","libraryId":"\(libraryID)","mediaType":"book",\
        "addedAt":\(addedAt(book)),"updatedAt":\(addedAt(book)),"isMissing":false,"isInvalid":false,\
        "numFiles":\(max(book.tracks.count, 1)),"size":0,\
        "media":{"id":"\(book.id)-media","coverPath":"/demo/\(book.cover).png",\
        "duration":\(duration),"numTracks":\(book.tracks.count),\
        "metadata":{"title":"\(escaped(book.title))","titleIgnorePrefix":"\(escaped(book.title))",\
        "subtitle":"","authorName":"\(escaped(book.author))",\
        "narratorName":"\(escaped(book.narrator ?? ""))","seriesName":"",\
        "publishedYear":"\(book.year)",\
        "description":"\(escaped(book.blurb))",\
        "genres":["Classics"],"explicit":false,"language":"English"},\
        "chapters":[\(chapters)],"audioFiles":[\(audioFiles)],\
        "numAudioFiles":\(book.tracks.count)\(ebookFile)}}
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

        let duration = book.tracks.reduce(0) { $0 + $1.duration }
        return """
        {"id":"\(sessionID)","libraryItemId":"\(book.id)","episodeId":null,\
        "displayTitle":"\(escaped(book.title))","displayAuthor":"\(escaped(book.author))",\
        "coverPath":"/demo/\(book.cover).png","duration":\(duration),\
        "playMethod":0,"currentTime":0,"startTime":0,"timeListening":0,\
        "startedAt":\(addedAt(book)),"updatedAt":\(addedAt(book)),\
        "chapters":[\(chaptersJSON(book))],"audioTracks":[\(tracks)]}
        """
    }

    private static func chaptersJSON(_ book: Book) -> String {
        book.tracks.enumerated().map { index, track in
            """
            {"id":\(index),"start":\(track.offset),\
            "end":\(track.offset + track.duration),"title":"\(escaped(track.title))"}
            """
        }.joined(separator: ",")
    }

    /// Quotation marks and backslashes are the only characters these strings
    /// can contain that would break the JSON; everything else is ours and plain.
    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
