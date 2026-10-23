import Foundation
import Testing
@testable import ABSKit
@testable import DemoKit

/// The demo payloads are written by hand, so they can drift away from the
/// decoders that have to read them. Every test here decodes one with the
/// app's real decoder: if a model changes shape, this fails loudly instead of
/// the sample library quietly turning up empty for a reviewer.
@Suite("Demo library payloads")
struct DemoCataloguePayloadTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ABSJSON.decoder.decode(type, from: Data(json.utf8))
    }

    @Test("The status payload decodes and looks like Audiobookshelf")
    func statusDecodes() throws {
        let status = try decode(ServerStatus.self, DemoCatalogue.statusJSON)
        #expect(status.looksLikeAudiobookshelf)
        #expect(status.serverVersion == "2.37.1")
    }

    @Test("The login payload decodes with both tokens")
    func loginDecodes() throws {
        let response = try decode(
            LoginResponse.self,
            DemoCatalogue.loginJSON(accessToken: "a", refreshToken: "r")
        )
        #expect(response.user.accessToken == "a")
        #expect(response.user.refreshToken == "r")
        #expect(response.userDefaultLibraryId == DemoCatalogue.libraryID)
    }

    @Test("The libraries payload decodes through its wrapper")
    func librariesDecode() throws {
        let response = try decode(ABSLibrariesResponse.self, DemoCatalogue.librariesJSON)
        #expect(response.libraries.count == 1)
        #expect(response.libraries.first?.id == DemoCatalogue.libraryID)
    }

    @Test("Each book is added before the one in front of it")
    func addedDatesAreStaggered() throws {
        let page = try decode(ABSLibraryItemsPage.self, DemoCatalogue.libraryItemsJSON)
        let dates = page.results.compactMap(\.addedAt)
        #expect(dates.count == DemoCatalogue.books.count)
        // Strictly descending: equal dates would collapse "Recently added"
        // back into an alphabetical list.
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test("The items page decodes and carries every demo book")
    func itemsPageDecodes() throws {
        let page = try decode(ABSLibraryItemsPage.self, DemoCatalogue.libraryItemsJSON)
        #expect(page.results.count == DemoCatalogue.books.count)
        #expect(page.total == DemoCatalogue.books.count)

        let titles = page.results.compactMap(\.media?.metadata.title)
        #expect(titles.contains("Alice's Adventures in Wonderland"))
    }

    @Test("Each item decodes on its own, with dates read as epoch milliseconds")
    func itemDecodes() throws {
        for book in DemoCatalogue.books {
            let item = try decode(ABSLibraryItem.self, DemoCatalogue.itemJSON(book))
            #expect(item.id == book.id)
            #expect(item.libraryId == DemoCatalogue.libraryID)
            // Compared as an interval, not a calendar year: the instant is
            // New Year in UTC and the evening before in a western timezone,
            // so asserting the year makes the test depend on where it runs.
            // A date read as seconds rather than milliseconds would land in
            // 1970 and miss by decades, which is what this catches.
            //
            // The window allows for the per-book stagger, which walks the
            // dates back a day at a time so "Recently added" has something
            // true to sort on.
            let addedAt = try #require(item.addedAt)
            let drift = 1_735_689_600 - addedAt.timeIntervalSince1970
            #expect(drift >= -1)
            #expect(drift < 86_400 * Double(DemoCatalogue.books.count))
        }
    }

    @Test("The playback session decodes with tracks the engine can use")
    func playbackSessionDecodes() throws {
        let book = try #require(DemoCatalogue.book(id: "demo-alice"))
        let session = try decode(
            ABSPlaybackSession.self,
            DemoCatalogue.playJSON(book, sessionID: "s")
        )
        #expect(session.libraryItemId == book.id)
        #expect(session.orderedTracks.count == book.tracks.count)
        #expect(session.orderedChapters.count == book.tracks.count)

        // Relative, like a real server's — the client supplies its own auth.
        let first = try #require(session.orderedTracks.first)
        #expect(first.contentUrl?.hasPrefix("/api/items/") == true)
        #expect(first.contentUrl?.contains("://") == false)
    }
}

@Suite("Demo library contents")
struct DemoCatalogueContentTests {
    @Test("The manifest decodes and is not empty")
    func manifestLoads() {
        #expect(DemoCatalogue.books.count >= 5)
        #expect(DemoCatalogue.books.allSatisfy { !$0.title.isEmpty })
        #expect(DemoCatalogue.books.allSatisfy { !$0.author.isEmpty })
        // Ids must be unique, or `book(id:)` returns an arbitrary one.
        #expect(Set(DemoCatalogue.books.map(\.id)).count == DemoCatalogue.books.count)
    }

    @Test("Every book's cover is actually in the bundle")
    func coversExist() {
        for book in DemoCatalogue.books {
            #expect(DemoBundle.url(named: book.cover, extension: "png") != nil)
        }
    }

    @Test("Something to listen to and something to read, or the demo shows nothing off")
    func libraryHasBothKinds() {
        #expect(DemoCatalogue.books.contains { !$0.tracks.isEmpty })
        #expect(DemoCatalogue.books.contains { $0.file?.ext == "epub" })
        #expect(DemoCatalogue.books.contains { $0.file?.ext == "cbz" })
    }

    @Test("Every audio track is actually in the bundle")
    func audioExists() {
        for book in DemoCatalogue.books {
            for track in book.tracks {
                #expect(DemoBundle.url(named: track.resource, extension: "m4a") != nil)
            }
        }
    }

    @Test("Every ebook and comic is actually in the bundle")
    func filesExist() throws {
        for book in DemoCatalogue.books {
            guard let file = book.file else { continue }
            #expect(DemoBundle.url(named: file.resource, extension: file.ext) != nil)
        }
    }

    @Test("Every book's track offsets run end to end, so chapter marks land correctly")
    func offsetsAreContiguous() {
        for book in DemoCatalogue.books {
            var expected: TimeInterval = 0
            for track in book.tracks {
                #expect(abs(track.offset - expected) < 0.001, "\(book.title) is misaligned")
                #expect(track.duration > 0, "\(book.title) has a zero-length chapter")
                expected += track.duration
            }
        }
    }

    @Test("A demo book reports bundled tracks; a real one reports none")
    func localTracksOnlyForDemoBooks() {
        #expect(DemoMode.localTracks(forItemID: "demo-alice").count == 3)
        #expect(DemoMode.localTracks(forItemID: "li_somethingreal").isEmpty)
        #expect(DemoMode.localFile(forItemID: "demo-mobydick") != nil)
        #expect(DemoMode.localFile(forItemID: "li_somethingreal") == nil)
    }
}

@Suite("Demo URL protocol")
struct DemoURLProtocolTests {
    private func request(_ method: String, _ path: String) -> URLRequest {
        var request = URLRequest(url: DemoMode.baseURL.appending(path: path))
        request.httpMethod = method
        return request
    }

    @Test("It claims the demo host and nothing else")
    func claimsOnlyItsOwnHost() {
        #expect(DemoURLProtocol.canInit(with: request("GET", "/status")))

        for other in ["https://books.example.com/status",
                      "http://192.168.1.10:13378/status",
                      "https://api.hardcover.app/v1/graphql"] {
            var request = URLRequest(url: URL(string: other)!)
            request.httpMethod = "GET"
            #expect(!DemoURLProtocol.canInit(with: request))
        }
    }

    @Test("It answers the routes a launch actually makes")
    func answersTheLaunchPath() throws {
        for (method, path) in [("GET", "/status"), ("POST", "/login"),
                               ("GET", "/api/me"), ("GET", "/api/libraries"),
                               ("GET", "/api/libraries/demo-library/items")] {
            let (status, body, type) = DemoURLProtocol.respond(to: request(method, path))
            #expect(status == 200)
            #expect(type == "application/json")
            #expect(!body.isEmpty)
        }
    }

    @Test("Covers come back as image bytes, not JSON")
    func servesCovers() {
        let (status, body, type) = DemoURLProtocol.respond(
            to: request("GET", "/api/items/demo-alice/cover")
        )
        #expect(status == 200)
        #expect(type == "image/png")
        #expect(body.count > 1_000)
        // PNG magic number: a JSON error page would not have it.
        #expect(body.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Audio files come back as audio")
    func servesAudio() {
        let (status, body, type) = DemoURLProtocol.respond(
            to: request("GET", "/api/items/demo-alice/file/alice-1")
        )
        #expect(status == 200)
        #expect(type == "audio/mp4")
        #expect(body.count > 10_000)
    }

    @Test("Writes are accepted rather than failed, because the demo is read-only")
    func acceptsWrites() {
        for (method, path) in [("PATCH", "/api/me/progress/demo-alice"),
                               ("POST", "/api/session/demo-session/sync"),
                               ("POST", "/api/session/demo-session/close")] {
            let (status, _, _) = DemoURLProtocol.respond(to: request(method, path))
            #expect(status == 200)
        }
    }

    @Test("Opening a demo book returns a playable session")
    func servesPlaybackSession() throws {
        let (status, body, _) = DemoURLProtocol.respond(
            to: request("POST", "/api/items/demo-alice/play")
        )
        #expect(status == 200)
        let session = try ABSJSON.decoder.decode(ABSPlaybackSession.self, from: body)
        #expect(session.orderedTracks.count == 3)
    }
}
