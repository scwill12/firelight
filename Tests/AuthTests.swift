import CryptoKit
import Foundation
import Testing
@testable import ABSKit
import ABSMockServer

@Suite("PKCE")
struct PKCETests {
    @Test("The challenge is the base64url SHA-256 of the verifier")
    func challengeDerivation() {
        let pair = PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let expected = Data(SHA256.hash(data: Data(pair.verifier.utf8))).base64URLEncodedString()
        #expect(pair.challenge == expected)
        #expect(pair.method == "S256")
    }

    @Test("base64url has no padding and no URL-unsafe characters")
    func urlSafety() {
        for _ in 0..<50 {
            let pair = PKCEPair()
            #expect(!pair.challenge.contains("="))
            #expect(!pair.challenge.contains("+"))
            #expect(!pair.challenge.contains("/"))
            #expect(!pair.verifier.contains("="))
        }
    }

    @Test("Verifier length sits inside RFC 7636's 43–128 characters")
    func verifierLength() {
        let pair = PKCEPair()
        #expect(pair.verifier.count >= 43)
        #expect(pair.verifier.count <= 128)
    }

    @Test("Every pair is different")
    func uniqueness() {
        let verifiers = Set((0..<100).map { _ in PKCEPair().verifier })
        #expect(verifiers.count == 100)
    }
}

@Suite("OpenID Connect request building")
struct OpenIDEndpointTests {
    @Test("The authorization URL carries everything ABS requires of a mobile flow")
    func authorizationURL() throws {
        let pkce = PKCEPair(verifier: "verifier-value")
        let url = try #require(ABSEndpoint.openIDAuthorizationURL(
            baseURL: URL(string: "https://example.com/abs")!,
            redirectURI: "firelight://oauth",
            pkce: pkce,
            state: "state-123"
        ))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/abs/auth/openid")

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        // Any one of these marks it as the mobile flow; we send all three.
        #expect(items["response_type"] == "code")
        #expect(items["redirect_uri"] == "firelight://oauth")
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "state-123")
    }

    @Test("The callback sends the verifier, never the challenge")
    func callbackRequest() {
        let request = ABSEndpoint.openIDCallback(code: "abc", state: "xyz", codeVerifier: "the-verifier")
        let items = Dictionary(uniqueKeysWithValues: request.query.map { ($0.name, $0.value) })
        #expect(request.path == "/auth/openid/callback")
        #expect(items["code"] == "abc")
        #expect(items["state"] == "xyz")
        #expect(items["code_verifier"] == "the-verifier")
        #expect(!request.requiresAuth)
    }

    @Test("Login carries the header that puts tokens in the body")
    func loginHeader() throws {
        let request = try ABSEndpoint.login(username: "cole", password: "pw")
        #expect(request.headers["x-return-tokens"] == "true")
        #expect(!request.retriesAfterTokenRefresh)
    }
}

@Suite("Auth store", .serialized)
struct AuthStoreTests {
    private func makeStore(_ server: MockABSServer) async -> AuthStore {
        let store = AuthStore(
            serverID: UUID(),
            keychain: KeychainStore(service: "com.colewilliams.firelight.tests.auth", accessGroup: nil)
        )
        await store.configure { server.makeClient() }
        return store
    }

    @Test("Stores and returns the access token")
    func persistsTokens() async throws {
        let server = MockABSServer()
        let store = await makeStore(server)
        let response = try await server.makeClient().login(username: "cole", password: "correct-horse")

        try await store.persist(response.user)
        #expect(await store.accessToken() == server.currentAccessToken)
        #expect(await store.storedRefreshToken() == server.currentRefreshToken)
        try await store.clear()
    }

    @Test("A pre-2.26 server's single long-lived token is still usable")
    func legacyToken() async throws {
        let server = MockABSServer(serverVersion: "2.20.0")
        let store = await makeStore(server)
        try await store.persist(ABSUser(id: "u", username: "cole", token: "legacy-token"))
        #expect(await store.accessToken() == "legacy-token")
        try await store.clear()
    }

    @Test("Concurrent 401s cause exactly one refresh")
    func refreshIsCoalesced() async throws {
        // ABS rotates the refresh token on every use, so a second concurrent
        // refresh would present a token the server has already retired.
        let server = MockABSServer()
        let store = await makeStore(server)
        try await store.persist(ABSUser(
            id: "u",
            username: "cole",
            accessToken: server.currentAccessToken,
            refreshToken: server.currentRefreshToken
        ))

        async let first = store.refreshAccessToken()
        async let second = store.refreshAccessToken()
        async let third = store.refreshAccessToken()
        let tokens = try await [first, second, third]

        #expect(server.requests(matching: "/auth/refresh").count == 1)
        #expect(Set(tokens.compactMap { $0 }).count == 1)
        #expect(tokens.first ?? nil == server.currentAccessToken)
        try await store.clear()
    }

    @Test("A refused refresh clears the session instead of retrying forever")
    func refusedRefreshClears() async throws {
        let server = MockABSServer()
        let store = await makeStore(server)
        try await store.persist(ABSUser(
            id: "u",
            username: "cole",
            accessToken: server.currentAccessToken,
            refreshToken: server.currentRefreshToken
        ))
        server.behaviour.refreshTokenIsRejected = true

        await #expect(throws: APIError.unauthorized) { _ = try await store.refreshAccessToken() }
        #expect(await store.hasStoredSession() == false)
    }

    @Test("With no refresh token there is nothing to refresh, and no crash")
    func noRefreshToken() async throws {
        let server = MockABSServer()
        let store = await makeStore(server)
        try await store.clear()
        #expect(try await store.refreshAccessToken() == nil)
    }
}

@Suite("Custom header store", .serialized)
struct CustomHeaderStoreTests {
    @Test("Headers survive a round trip and reach the client")
    func roundTrip() async throws {
        let serverID = UUID()
        let store = CustomHeaderStore(
            serverID: serverID,
            keychain: KeychainStore(service: "com.colewilliams.firelight.tests.headers", accessGroup: nil)
        )
        try store.save(["CF-Access-Client-Id": "abc", "CF-Access-Client-Secret": "shh"])
        #expect(await store.customHeaders()["CF-Access-Client-Id"] == "abc")

        try store.save([:])
        #expect(await store.customHeaders().isEmpty)
    }

    @Test("Blank header names are dropped rather than sent")
    func dropsBlankNames() throws {
        let store = CustomHeaderStore(
            serverID: UUID(),
            keychain: KeychainStore(service: "com.colewilliams.firelight.tests.headers", accessGroup: nil)
        )
        try store.save(["  ": "value", "Good": "value"])
        #expect(store.stored() == ["Good": "value"])
        try store.save([:])
    }
}
