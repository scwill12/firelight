import Foundation

/// Answers the Audiobookshelf API for the demo library.
///
/// Registered in the app's `URLSession` configuration, it claims requests to
/// `DemoMode.host` and nothing else, so every other server goes over the real
/// network untouched. The app above it cannot tell the difference: the same
/// client, the same decoders, the same screens.
///
/// What it cannot cover is audio playback. `AVPlayer` does not load through
/// the URL loading system, so a demo book is presented to the player as
/// *already downloaded* — `DemoMode.localTracks` hands it bundled file URLs,
/// which is the app's ordinary offline path rather than a special case.
public final class DemoURLProtocol: URLProtocol, @unchecked Sendable {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return DemoMode.isDemo(url: url)
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        let (status, body, contentType) = Self.respond(to: request)
        let response = HTTPURLResponse(
            url: request.url ?? DemoMode.baseURL,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}

    // MARK: - Routing

    static func respond(to request: URLRequest) -> (Int, Data, String) {
        guard let url = request.url else { return (400, Data(), "application/json") }
        let path = url.path()
        let method = request.httpMethod ?? "GET"

        // Cover art and file bytes come straight out of the bundle.
        if let resource = coverResource(forPath: path) {
            if let data = DemoBundle.data(named: resource, extension: "png") {
                return (200, data, "image/png")
            }
            return (404, Data(), "application/json")
        }
        if let (name, ext, type) = fileResource(forPath: path) {
            if let data = DemoBundle.data(named: name, extension: ext) {
                return (200, data, type)
            }
            return (404, Data(), "application/json")
        }

        let json: String
        switch (method, path) {
        case ("GET", "/status"):
            json = DemoCatalogue.statusJSON
        case ("GET", "/ping"):
            json = #"{"success":true}"#
        case ("POST", "/login"):
            json = DemoCatalogue.loginJSON(accessToken: "demo-access", refreshToken: "demo-refresh")
        case ("POST", "/auth/refresh"):
            json = DemoCatalogue.loginJSON(accessToken: "demo-access", refreshToken: "demo-refresh")
        case ("GET", "/api/me"):
            json = DemoCatalogue.meJSON
        case ("GET", "/api/libraries"):
            json = DemoCatalogue.librariesJSON
        default:
            if method == "GET", path.hasSuffix("/items") {
                json = DemoCatalogue.libraryItemsJSON
            } else if method == "POST", path.contains("/play") {
                guard let book = book(inPath: path) else { return (404, Data(), "application/json") }
                json = DemoCatalogue.playJSON(book, sessionID: "demo-session")
            } else if method == "GET", let book = book(inPath: path), path.hasSuffix(book.id) {
                json = DemoCatalogue.itemJSON(book)
            } else {
                // Everything the demo does not model — progress writes,
                // session syncs, bookmarks — is accepted and discarded. The
                // demo library is read-only on purpose, and an error here
                // would surface as a failure banner over a working screen.
                json = #"{"success":true}"#
            }
        }
        return (200, Data(json.utf8), "application/json")
    }

    /// `/api/items/{id}/cover`
    private static func coverResource(forPath path: String) -> String? {
        guard path.hasSuffix("/cover"), let book = book(inPath: path) else { return nil }
        return book.coverResource
    }

    /// `/api/items/{id}/file/{ino}` and `/api/items/{id}/ebook`
    private static func fileResource(forPath path: String) -> (String, String, String)? {
        guard let book = book(inPath: path) else { return nil }
        if let ino = path.components(separatedBy: "/file/").last, path.contains("/file/") {
            if book.tracks.contains(where: { $0.resource == ino }) {
                return (ino, "m4a", "audio/mp4")
            }
            if let file = book.fileResource, let ext = book.fileExtension, ino.hasPrefix(file) {
                return (file, ext, "application/octet-stream")
            }
        }
        if path.hasSuffix("/ebook"), let file = book.fileResource, let ext = book.fileExtension {
            return (file, ext, "application/octet-stream")
        }
        return nil
    }

    private static func book(inPath path: String) -> DemoCatalogue.Book? {
        DemoCatalogue.books.first { path.contains($0.id) }
    }
}

/// Where the bundled demo files live.
///
/// `Bundle.module` is internal to the package, so anything outside `DemoKit`
/// that needs a file — the player, for its already-downloaded tracks — asks
/// through here.
public enum DemoBundle {
    public static func url(named name: String, extension ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext)
    }

    public static func data(named name: String, extension ext: String) -> Data? {
        url(named: name, extension: ext).flatMap { try? Data(contentsOf: $0) }
    }
}
