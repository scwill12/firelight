import Foundation
import Testing
@testable import ABSKit

@Suite("Server version")
struct ServerVersionTests {
    @Test("Parses the shapes ABS actually reports")
    func parsing() throws {
        #expect(ServerVersion("2.26.0") == ServerVersion(major: 2, minor: 26, patch: 0))
        #expect(ServerVersion("v2.17.5") == ServerVersion(major: 2, minor: 17, patch: 5))
        #expect(ServerVersion("2.26") == ServerVersion(major: 2, minor: 26, patch: 0))
        #expect(ServerVersion("3") == ServerVersion(major: 3, minor: 0, patch: 0))
        #expect(ServerVersion("")  == nil)
        #expect(ServerVersion("not-a-version") == nil)
    }

    @Test("Orders by major, then minor, then patch")
    func ordering() {
        #expect(ServerVersion("2.9.0")! < ServerVersion("2.10.0")!)
        #expect(ServerVersion("2.26.1")! > ServerVersion("2.26.0")!)
        #expect(ServerVersion("3.0.0")! > ServerVersion("2.99.99")!)
    }

    @Test("A beta of a release has that release's endpoints, so it compares equal")
    func prerelease() throws {
        let beta = try #require(ServerVersion("2.26.0-beta.1"))
        #expect(beta == ServerVersion("2.26.0"))
        #expect(beta.prerelease == "beta.1")
        #expect(beta.description == "2.26.0-beta.1")
        #expect(!(beta < ServerVersion("2.26.0")!))
    }
}

@Suite("Feature table")
struct FeatureTableTests {
    @Test("Gates on the minimum version")
    func gating() {
        let modern = FeatureTable(serverVersion: ServerVersion("2.26.0"))
        #expect(modern.supports(.refreshTokenAuth))
        #expect(modern.supports(.tokensInLoginResponseBody))

        let old = FeatureTable(serverVersion: ServerVersion("2.25.1"))
        #expect(!old.supports(.refreshTokenAuth))
    }

    @Test("An unknown version is treated as too old, never as capable")
    func unknownVersion() {
        let unknown = FeatureTable(serverVersion: nil)
        for feature in ABSFeature.allCases {
            #expect(!unknown.supports(feature))
        }
        #expect(unknown.unsupportedFeatures.count == ABSFeature.allCases.count)
    }

    @Test("require throws the error the UI shows")
    func requireThrows() throws {
        let old = FeatureTable(serverVersion: ServerVersion("2.20.0"))
        #expect(throws: APIError.self) { try old.require(.apiKeys) }

        do {
            try old.require(.apiKeys)
            Issue.record("Expected a throw")
        } catch let error as APIError {
            guard case .unsupportedByServer(_, let required, let actual) = error else {
                Issue.record("Wrong case: \(error)")
                return
            }
            #expect(required == ServerVersion("2.26.0"))
            #expect(actual == ServerVersion("2.20.0"))
        }
    }
}

@Suite("Server URL parsing")
struct ServerURLParserTests {
    @Test("Defaults to https when no scheme is given")
    func addsScheme() throws {
        let url = try #require(ServerURLParser.parse("books.example.com"))
        #expect(url.absoluteString == "https://books.example.com")
    }

    @Test("Keeps the sub-path, because ABS can be hosted under one")
    func keepsBasePath() throws {
        let url = try #require(ServerURLParser.parse("https://example.com/audiobookshelf"))
        #expect(url.absoluteString == "https://example.com/audiobookshelf")
    }

    @Test("Drops a trailing slash and a pasted /login")
    func trimsNoise() throws {
        #expect(ServerURLParser.parse("https://example.com/")?.absoluteString == "https://example.com")
        #expect(ServerURLParser.parse("https://example.com/login")?.absoluteString == "https://example.com")
        #expect(ServerURLParser.parse("https://example.com/abs/login")?.absoluteString == "https://example.com/abs")
    }

    @Test("Keeps an explicit http scheme and a port")
    func keepsSchemeAndPort() throws {
        let url = try #require(ServerURLParser.parse("http://192.168.1.10:13378"))
        #expect(url.absoluteString == "http://192.168.1.10:13378")
    }

    @Test("Rejects what isn't a server address")
    func rejectsJunk() {
        #expect(ServerURLParser.parse("") == nil)
        #expect(ServerURLParser.parse("   ") == nil)
        #expect(ServerURLParser.parse("ftp://example.com") == nil)
    }
}

@Suite("Redaction")
struct RedactionTests {
    @Test("A logged URL keeps its path but never its host")
    func urlRedaction() {
        let url = URL(string: "https://books.example.com:8443/abs/api/libraries?token=secret")
        let redacted = Redaction.url(url)
        #expect(redacted == "https://<server>/abs/api/libraries")
        #expect(!redacted.contains("books.example.com"))
        #expect(!redacted.contains("secret"))
    }

    @Test("A token is never reproduced")
    func tokenRedaction() {
        let redacted = Redaction.token("eyJhbGciOiJIUzI1NiJ9.abc")
        #expect(!redacted.contains("eyJ"))
        #expect(redacted == "<token:24ch>")
        #expect(Redaction.token(nil) == "<none>")
    }

    @Test("Only harmless headers are printed in full")
    func headerRedaction() {
        let redacted = Redaction.headers([
            "Authorization": "Bearer abc123",
            "CF-Access-Client-Secret": "shhh",
            "Accept": "application/json",
        ])
        #expect(redacted["Authorization"] == "<redacted>")
        #expect(redacted["CF-Access-Client-Secret"] == "<redacted>")
        #expect(redacted["Accept"] == "application/json")
    }
}

@Suite("Keychain store", .serialized)
struct KeychainStoreTests {
    private var store: KeychainStore {
        // No access group: the test host's entitlements are not the app's.
        KeychainStore(service: "com.colewilliams.firelight.tests", accessGroup: nil)
    }

    @Test("Round-trips a value")
    func roundTrip() throws {
        let key = "test.\(UUID().uuidString)"
        try store.setString("hello", for: key)
        #expect(try store.string(for: key) == "hello")
        try store.remove(key)
        #expect(try store.string(for: key) == nil)
    }

    @Test("Overwrites rather than duplicating")
    func overwrites() throws {
        let key = "test.\(UUID().uuidString)"
        try store.setString("first", for: key)
        try store.setString("second", for: key)
        #expect(try store.string(for: key) == "second")
        try store.remove(key)
    }

    @Test("A missing key reads as nil, not an error")
    func missingKey() throws {
        #expect(try store.string(for: "test.absent.\(UUID().uuidString)") == nil)
    }

    @Test("Codable values survive the trip")
    func codable() throws {
        let key = "test.\(UUID().uuidString)"
        let headers = ["CF-Access-Client-Id": "abc", "X-Extra": "def"]
        try store.set(headers, for: key)
        #expect(try store.value([String: String].self, for: key) == headers)
        try store.remove(key)
    }

    @Test("Keychain keys are distinct per server")
    func keyNamespacing() {
        let a = UUID(), b = UUID()
        #expect(KeychainKey.accessToken(serverID: a) != KeychainKey.accessToken(serverID: b))
        #expect(KeychainKey.accessToken(serverID: a) != KeychainKey.refreshToken(serverID: a))
    }
}
