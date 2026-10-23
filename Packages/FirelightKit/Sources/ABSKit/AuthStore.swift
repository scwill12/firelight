import Foundation

/// Holds one server's tokens, persists them to the shared Keychain, and renews
/// them when they expire.
///
/// Concurrency matters here: several requests can 401 at once, and each would
/// otherwise start its own refresh. ABS rotates the refresh token on every use,
/// so a second concurrent refresh would present a token the server has already
/// retired and sign the user out. One in-flight refresh is shared by every
/// caller.
public actor AuthStore: AccessTokenProviding {
    private let serverID: UUID
    private let keychain: KeychainStore

    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var inFlightRefresh: Task<String?, Error>?

    /// Builds a client that can call `/auth/refresh`. Supplied after init
    /// because the client needs this store for its other calls.
    private var refreshClientProvider: (@Sendable () -> ABSClient)?

    public init(serverID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.serverID = serverID
        self.keychain = keychain
    }

    public func configure(refreshClientProvider: @escaping @Sendable () -> ABSClient) {
        self.refreshClientProvider = refreshClientProvider
    }

    // MARK: - AccessTokenProviding

    public func accessToken() async -> String? {
        if let cachedAccessToken { return cachedAccessToken }
        cachedAccessToken = try? keychain.string(for: KeychainKey.accessToken(serverID: serverID))
        return cachedAccessToken
    }

    public func refreshAccessToken() async throws -> String? {
        if let inFlightRefresh { return try await inFlightRefresh.value }

        guard let refreshClientProvider else { return nil }
        guard let refreshToken = currentRefreshToken() else { return nil }

        let task = Task<String?, Error> { [serverID] in
            do {
                let response = try await refreshClientProvider().refresh(refreshToken: refreshToken)
                try self.persist(response.user)
                return response.user.accessToken
            } catch let error as APIError {
                // A refused refresh means the session is gone for good; clear it
                // so nothing retries with a token the server has retired.
                if case .unauthorized = error { try? self.clear() }
                if case .forbidden = error { try? self.clear() }
                _ = serverID
                throw error
            }
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    // MARK: - Lifecycle

    /// Stores the tokens from a successful sign-in or refresh.
    public func persist(_ user: ABSUser) throws {
        if let accessToken = user.accessToken {
            cachedAccessToken = accessToken
            try keychain.setString(accessToken, for: KeychainKey.accessToken(serverID: serverID))
        } else if let legacy = user.token {
            // Pre-2.26 servers issue one long-lived token and no refresh token.
            cachedAccessToken = legacy
            try keychain.setString(legacy, for: KeychainKey.legacyToken(serverID: serverID))
            try keychain.setString(legacy, for: KeychainKey.accessToken(serverID: serverID))
        }
        if let refreshToken = user.refreshToken {
            cachedRefreshToken = refreshToken
            try keychain.setString(refreshToken, for: KeychainKey.refreshToken(serverID: serverID))
        }
    }

    public func clear() throws {
        cachedAccessToken = nil
        cachedRefreshToken = nil
        try keychain.remove(KeychainKey.accessToken(serverID: serverID))
        try keychain.remove(KeychainKey.refreshToken(serverID: serverID))
        try keychain.remove(KeychainKey.legacyToken(serverID: serverID))
    }

    public func hasStoredSession() -> Bool {
        (try? keychain.string(for: KeychainKey.accessToken(serverID: serverID))) ?? nil != nil
    }

    /// The refresh token, for the sign-out call that invalidates it server-side.
    public func storedRefreshToken() -> String? { currentRefreshToken() }

    private func currentRefreshToken() -> String? {
        if let cachedRefreshToken { return cachedRefreshToken }
        cachedRefreshToken = try? keychain.string(for: KeychainKey.refreshToken(serverID: serverID))
        return cachedRefreshToken
    }
}

/// Per-server proxy headers, kept in the Keychain because they are credentials
/// in every sense that matters (Cloudflare Access service tokens, Authelia
/// shared secrets).
public struct CustomHeaderStore: CustomHeaderProviding {
    private let serverID: UUID
    private let keychain: KeychainStore

    public init(serverID: UUID, keychain: KeychainStore = KeychainStore()) {
        self.serverID = serverID
        self.keychain = keychain
    }

    public func customHeaders() async -> [String: String] {
        stored()
    }

    public func stored() -> [String: String] {
        (try? keychain.value([String: String].self, for: KeychainKey.customHeaders(serverID: serverID))) ?? [:]
    }

    public func save(_ headers: [String: String]) throws {
        let cleaned = headers.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        if cleaned.isEmpty {
            try keychain.remove(KeychainKey.customHeaders(serverID: serverID))
        } else {
            try keychain.set(cleaned, for: KeychainKey.customHeaders(serverID: serverID))
        }
    }
}
