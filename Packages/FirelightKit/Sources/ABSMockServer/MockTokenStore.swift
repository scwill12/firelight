import ABSKit
import Foundation

/// An `AccessTokenProviding` backed by a mock server, so tests can exercise the
/// 401 → refresh → retry path the real auth store will take in Phase 1.
public actor MockTokenStore: AccessTokenProviding {
    private let server: MockABSServer
    private var token: String?
    private var refreshToken: String
    public private(set) var refreshCallCount = 0

    public init(server: MockABSServer, accessToken: String? = nil, refreshToken: String? = nil) {
        self.server = server
        self.token = accessToken ?? server.currentAccessToken
        self.refreshToken = refreshToken ?? server.currentRefreshToken
    }

    public func accessToken() async -> String? { token }

    public func refreshAccessToken() async throws -> String? {
        refreshCallCount += 1
        let client = server.makeClient()
        let response = try await client.refresh(refreshToken: refreshToken)
        token = response.user.accessToken
        if let newRefresh = response.user.refreshToken {
            refreshToken = newRefresh
        }
        return token
    }
}
