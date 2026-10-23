import ABSKit
import Foundation
import Observation
import Persistence

/// Owns which server and account the app is acting as, and how it reaches them.
///
/// Everything that needs a client asks this; nothing builds one for itself.
@MainActor
@Observable
public final class SessionController {
    public private(set) var servers: [ServerDescriptor] = []
    public private(set) var users: [UserSummary] = []
    public private(set) var activeUser: UserSummary?

    /// Which of the active server's addresses answered last.
    public private(set) var activeAddress: ActiveAddress?
    public private(set) var activeServerVersion: ServerVersion?
    public private(set) var isConnecting = false
    /// Set when the active server could not be reached; the app still works
    /// from cache, so this is a notice, not a failure.
    public private(set) var isOffline = false

    /// Called whenever the active connection changes — a different server or
    /// account, a new address, or a fresh sign-in.
    ///
    /// Covers are fetched outside the API client, so nothing else would tell
    /// them that a base URL now exists; before this hook, a server added after
    /// launch showed placeholders until the app was relaunched.
    @ObservationIgnored public var onActiveConnectionChange: (@MainActor () async -> Void)?

    @ObservationIgnored let factory: ConnectionFactory
    @ObservationIgnored private let store: ServerStore?
    @ObservationIgnored private var resolvedURLs: [UUID: URL] = [:]

    public init(keychain: KeychainStore, persistence: PersistenceController?) {
        self.factory = ConnectionFactory(keychain: keychain)
        self.store = persistence.map { ServerStore(modelContainer: $0.container) }
    }

    public var featureTable: FeatureTable {
        FeatureTable(serverVersion: activeServerVersion)
    }

    public var activeServer: ServerDescriptor? {
        guard let activeUser else { return nil }
        return servers.first { $0.id == activeUser.serverID }
    }

    // MARK: - Loading

    public func load() async {
        guard let store else { return }
        do {
            servers = try await store.servers()
            users = try await store.allUsers()
            activeUser = try await store.activeUser()
            SharedState.serverCount = servers.count
        } catch {
            servers = []
            users = []
        }
        await onActiveConnectionChange?()
    }

    /// Finds the reachable address for the active server and remembers it.
    public func connect() async {
        guard let server = activeServer else { return }
        isConnecting = true
        defer { isConnecting = false }

        let resolver = factory.resolver(for: server.id)
        guard let resolved = await resolver.resolve(server) else {
            isOffline = true
            activeAddress = nil
            await onActiveConnectionChange?()
            return
        }

        isOffline = false
        activeAddress = resolved.kind
        resolvedURLs[server.id] = resolved.url
        // The share extension builds its own client from this.
        SharedState.activeServer = (id: server.id, baseURL: resolved.url)

        // Refresh the version while we are here; the feature table depends on it.
        let client = factory.anonymousClient(baseURL: resolved.url, serverID: server.id)
        let version = try? await client.status().serverVersion
        activeServerVersion = version.flatMap(ServerVersion.init)
        try? await store?.recordConnection(id: server.id, address: resolved.kind, serverVersion: version)
        await onActiveConnectionChange?()
    }

    /// The client for the active account, or nil when nothing is signed in or
    /// no address is reachable.
    public func client() -> ABSClient? {
        guard let server = activeServer, let url = resolvedURLs[server.id] else { return nil }
        return factory.authenticatedClient(serverID: server.id, baseURL: url)
    }

    public func baseURL(for serverID: UUID) -> URL? { resolvedURLs[serverID] }

    // MARK: - Adding a server

    /// Adds a server and signs in with a password, in one step, because to the
    /// user they are one step.
    public func addServer(
        displayName: String,
        remoteURLText: String,
        localURLText: String?,
        username: String,
        password: String,
        customHeaders: [String: String] = [:]
    ) async throws -> UserSummary {
        guard let store else { throw SessionError.storeUnavailable }
        guard let remoteURL = ServerURLParser.parse(remoteURLText) else { throw SessionError.invalidAddress }
        let localURL = localURLText.flatMap { $0.isEmpty ? nil : ServerURLParser.parse($0) }

        let status = try await verifiedStatus(at: remoteURL, headers: customHeaders)
        let descriptor = try await store.addServer(
            displayName: displayName.isEmpty ? (remoteURL.host() ?? "Audiobookshelf") : displayName,
            localURL: localURL,
            remoteURL: remoteURL,
            serverVersion: status.serverVersion
        )

        do {
            // Save the headers first: everything from here on goes through the
            // stored set, including the sign-in itself.
            try? factory.headerStore(for: descriptor.id).save(customHeaders)
            return try await completeSignIn(
                serverID: descriptor.id,
                baseURL: remoteURL,
                response: try await factory
                    .anonymousClient(baseURL: remoteURL, serverID: descriptor.id)
                    .login(username: username, password: password)
            )
        } catch {
            // Don't leave a half-added server behind a failed sign-in.
            try? await store.removeServer(id: descriptor.id)
            await load()
            throw Self.signInError(from: error)
        }
    }

    /// Adds a server and signs in through single sign-on.
    public func addServerWithOpenID(
        displayName: String,
        remoteURLText: String,
        localURLText: String?,
        customHeaders: [String: String] = [:]
    ) async throws -> UserSummary {
        guard let store else { throw SessionError.storeUnavailable }
        guard let remoteURL = ServerURLParser.parse(remoteURLText) else { throw SessionError.invalidAddress }
        let localURL = localURLText.flatMap { $0.isEmpty ? nil : ServerURLParser.parse($0) }

        let status = try await verifiedStatus(at: remoteURL, headers: customHeaders)
        guard status.supportsOpenIDConnect else { throw SessionError.openIDUnavailable }

        let descriptor = try await store.addServer(
            displayName: displayName.isEmpty ? (remoteURL.host() ?? "Audiobookshelf") : displayName,
            localURL: localURL,
            remoteURL: remoteURL,
            serverVersion: status.serverVersion
        )

        do {
            try? factory.headerStore(for: descriptor.id).save(customHeaders)
            let callback = try await OIDCSignInService().authorize(baseURL: remoteURL)
            let response = try await factory
                .anonymousClient(baseURL: remoteURL, serverID: descriptor.id)
                .completeOpenIDSignIn(
                    code: callback.code,
                    state: callback.state,
                    codeVerifier: callback.codeVerifier
                )
            return try await completeSignIn(serverID: descriptor.id, baseURL: remoteURL, response: response)
        } catch {
            try? await store.removeServer(id: descriptor.id)
            await load()
            throw Self.signInError(from: error)
        }
    }

    /// Signs an additional account into a server that is already configured.
    public func addAccount(serverID: UUID, username: String, password: String) async throws -> UserSummary {
        guard let store, let server = try await store.server(id: serverID) else {
            throw SessionError.storeUnavailable
        }
        let url = resolvedURLs[serverID] ?? server.remoteURL
        do {
            let response = try await factory
                .anonymousClient(baseURL: url, serverID: serverID)
                .login(username: username, password: password)
            return try await completeSignIn(serverID: serverID, baseURL: url, response: response)
        } catch {
            throw Self.signInError(from: error)
        }
    }

    // MARK: - Switching and signing out

    public func switchTo(user: UserSummary) async {
        guard let store else { return }
        try? await store.setActive(compositeID: user.id)
        await load()
        await connect()
    }

    public func signOut(user: UserSummary) async {
        guard let store else { return }
        let authStore = factory.authStore(for: user.serverID)

        // Tell the server first, while we still hold a usable token.
        if let url = resolvedURLs[user.serverID] {
            let refreshToken = await authStore.storedRefreshToken()
            let client = factory.authenticatedClient(serverID: user.serverID, baseURL: url)
            try? await client.logout(refreshToken: refreshToken)
        }
        try? await authStore.clear()
        try? await store.signOut(compositeID: user.id)

        await load()
        // Make some other account active rather than leaving the app in limbo.
        if activeUser == nil, let next = users.first {
            await switchTo(user: next)
        }
    }

    public func removeServer(id: UUID) async {
        guard let store else { return }
        try? await factory.authStore(for: id).clear()
        try? await factory.headerStore(for: id).save([:])
        try? await store.removeServer(id: id)
        resolvedURLs[id] = nil
        await load()
    }

    // MARK: - Server settings

    public func customHeaders(for serverID: UUID) -> [String: String] {
        factory.headerStore(for: serverID).stored()
    }

    public func saveCustomHeaders(_ headers: [String: String], for serverID: UUID) throws {
        try factory.headerStore(for: serverID).save(headers)
    }

    public func trustCertificate(fingerprintOf host: String, serverID: UUID) async -> Bool {
        guard let fingerprint = await factory.trust.rejectedFingerprint(forHost: host) else { return false }
        await factory.trust.trust(fingerprint, forHost: host)
        return true
    }

    public func updateAddresses(serverID: UUID, localURLText: String?, remoteURLText: String) async throws {
        guard let store else { throw SessionError.storeUnavailable }
        guard let remoteURL = ServerURLParser.parse(remoteURLText) else { throw SessionError.invalidAddress }
        let localURL = localURLText.flatMap { $0.isEmpty ? nil : ServerURLParser.parse($0) }
        try await store.updateServer(id: serverID, localURL: .some(localURL), remoteURL: remoteURL)
        await load()
        await connect()
    }

    // MARK: - Private

    private func verifiedStatus(at url: URL, headers: [String: String]) async throws -> ServerStatus {
        let status: ServerStatus
        do {
            status = try await factory
                .anonymousClient(baseURL: url, headers: StaticCustomHeaders(headers))
                .status()
        } catch {
            throw Self.signInError(from: error)
        }
        guard status.looksLikeAudiobookshelf else { throw SessionError.notAudiobookshelf }
        return status
    }

    private func completeSignIn(
        serverID: UUID,
        baseURL: URL,
        response: LoginResponse
    ) async throws -> UserSummary {
        guard let store else { throw SessionError.storeUnavailable }
        try await factory.authStore(for: serverID).persist(response.user)
        let summary = try await store.signIn(
            serverID: serverID,
            user: response.user,
            defaultLibraryID: response.userDefaultLibraryId
        )
        resolvedURLs[serverID] = baseURL
        await load()
        await connect()
        return summary
    }

    private static func signInError(from error: Error) -> SessionError {
        if let sessionError = error as? SessionError { return sessionError }
        guard let apiError = error as? APIError else {
            return .signInFailed("Sign-in didn't complete.")
        }
        switch apiError {
        case .unauthorized:
            return .signInFailed("That username and password didn't work.")
        case .unreachable:
            return .signInFailed("Can't reach the server.")
        case .untrustedCertificate:
            return .signInFailed("This server's certificate isn't trusted yet.")
        default:
            return .signInFailed(apiError.localizedDescription)
        }
    }
}
