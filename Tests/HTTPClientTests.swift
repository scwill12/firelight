import Foundation
import Testing
@testable import ABSKit
import ABSMockServer

@Suite("HTTP client")
struct HTTPClientTests {
    @Test("Builds URLs that preserve the server's sub-path")
    func basePathPreserved() throws {
        let client = URLSessionHTTPClient(baseURL: URL(string: "https://example.com/audiobookshelf")!)
        let url = try client.makeURL(for: HTTPRequest(path: "/api/libraries"))
        #expect(url.absoluteString == "https://example.com/audiobookshelf/api/libraries")
    }

    @Test("Appends query items without losing the path")
    func queryItems() throws {
        let client = URLSessionHTTPClient(baseURL: URL(string: "https://example.com")!)
        let request = HTTPRequest(path: "/api/libraries/lib-1/items", query: [URLQueryItem(name: "limit", value: "50")])
        let url = try client.makeURL(for: request)
        #expect(url.absoluteString == "https://example.com/api/libraries/lib-1/items?limit=50")
    }

    @Test("Reaches a server hosted under a sub-path end to end")
    func subPathRoundTrip() async throws {
        let server = MockABSServer(basePath: "/abs")
        let status = try await server.makeClient().status()
        #expect(status.serverVersion == "2.26.0")
        #expect(server.requests(matching: "/status").count == 1)
    }

    @Test("Sends the per-server custom headers on every request")
    func customHeaders() async throws {
        let server = MockABSServer()
        server.behaviour.requiredHeader = (name: "CF-Access-Client-Id", value: "abc123")

        let withoutHeaders = server.makeClient()
        await #expect(throws: APIError.forbidden) { try await withoutHeaders.status() }

        let withHeaders = server.makeClient(
            customHeaders: StaticCustomHeaders(["CF-Access-Client-Id": "abc123"])
        )
        let status = try await withHeaders.status()
        #expect(status.looksLikeAudiobookshelf)
    }

    @Test("Attaches the bearer token to authenticated calls only")
    func bearerToken() async throws {
        let server = MockABSServer()
        let tokens = MockTokenStore(server: server)
        let client = server.makeClient(tokens: tokens)

        _ = try await client.status()
        let statusRequest = try #require(server.requests(matching: "/status").first)
        #expect(statusRequest.header("Authorization") == nil)

        let user = try await client.me()
        #expect(user.username == "cole")
        let meRequest = try #require(server.requests(matching: "/api/me").first)
        #expect(meRequest.header("Authorization") == "Bearer \(server.currentAccessToken)")
    }

    @Test("A 401 refreshes the token once and retries the request")
    func refreshOn401() async throws {
        let server = MockABSServer()
        let tokens = MockTokenStore(server: server)
        let client = server.makeClient(tokens: tokens)

        server.behaviour.accessTokenIsExpired = true
        let user = try await client.me()

        #expect(user.username == "cole")
        #expect(await tokens.refreshCallCount == 1)
        // The first attempt 401s, then the refresh, then the retry.
        #expect(server.requests(matching: "/api/me").count == 2)
        #expect(server.requests(matching: "/auth/refresh").count == 1)
    }

    @Test("A rejected refresh surfaces as unauthorized, and does not loop")
    func refreshRejected() async throws {
        let server = MockABSServer()
        let tokens = MockTokenStore(server: server)
        let client = server.makeClient(tokens: tokens)

        server.behaviour.accessTokenIsExpired = true
        server.behaviour.refreshTokenIsRejected = true

        await #expect(throws: APIError.unauthorized) { try await client.me() }
        #expect(server.requests(matching: "/api/me").count == 1)
    }

    @Test("Maps status codes to the errors features act on")
    func statusMapping() async throws {
        let server = MockABSServer()
        let client = server.makeClient()

        server.behaviour.failEverythingWith = 403
        await #expect(throws: APIError.forbidden) { try await client.status() }

        server.behaviour.failEverythingWith = 404
        await #expect(throws: APIError.notFound) { try await client.status() }

        server.behaviour.failEverythingWith = 500
        await #expect(throws: APIError.self) { try await client.status() }
    }

    @Test("Extracts the server's own error message")
    func errorMessage() {
        let json = Data(#"{"error":"Invalid user or password"}"#.utf8)
        #expect(URLSessionHTTPClient.message(from: json) == "Invalid user or password")
        #expect(URLSessionHTTPClient.message(from: Data()) == nil)
        #expect(URLSessionHTTPClient.message(from: Data("<html>oops</html>".utf8)) == nil)
    }

    @Test("ping answers false rather than throwing, so addresses can be raced")
    func pingNeverThrows() async {
        let server = MockABSServer()
        #expect(await server.makeClient().ping())

        server.behaviour.failEverythingWith = 500
        #expect(await server.makeClient().ping() == false)
    }
}

@Suite("ABS client")
struct ABSClientTests {
    @Test("Decodes the status payload ABS actually sends")
    func statusDecoding() async throws {
        let server = MockABSServer(serverVersion: "2.17.5")
        let status = try await server.makeClient().status()

        #expect(status.app == "audiobookshelf")
        #expect(status.version == ServerVersion("2.17.5"))
        #expect(status.authMethods == ["local"])
        #expect(!status.supportsOpenIDConnect)
        #expect(!status.featureTable.supports(.refreshTokenAuth))
    }

    @Test("Login asks for the tokens in the body, not a cookie")
    func loginReturnsTokens() async throws {
        let server = MockABSServer()
        let response = try await server.makeClient().login(username: "cole", password: "correct-horse")

        #expect(response.user.username == "cole")
        #expect(response.user.accessToken == server.currentAccessToken)
        #expect(response.user.refreshToken == server.currentRefreshToken)
        #expect(response.userDefaultLibraryId == "lib-1")
        #expect(response.user.isAdmin)

        let request = try #require(server.requests(matching: "/login").first)
        #expect(request.header("x-return-tokens") == "true")
    }

    @Test("A wrong password is unauthorized, not a crash")
    func loginFails() async throws {
        let server = MockABSServer()
        await #expect(throws: APIError.unauthorized) {
            try await server.makeClient().login(username: "cole", password: "wrong")
        }
    }

    @Test("The refresh token goes in the header ABS reads")
    func refreshUsesHeader() async throws {
        let server = MockABSServer()
        let original = server.currentRefreshToken
        let response = try await server.makeClient().refresh(refreshToken: original)

        #expect(response.user.accessToken != nil)
        #expect(response.user.accessToken == server.currentAccessToken)

        let request = try #require(server.requests(matching: "/auth/refresh").first)
        #expect(request.header("x-refresh-token") == original)
    }

    @Test("bearerToken prefers the modern access token over the legacy one")
    func bearerPreference() {
        let modern = ABSUser(id: "1", username: "a", token: "legacy", accessToken: "modern")
        #expect(modern.bearerToken == "modern")
        let legacy = ABSUser(id: "1", username: "a", token: "legacy")
        #expect(legacy.bearerToken == "legacy")
    }
}
