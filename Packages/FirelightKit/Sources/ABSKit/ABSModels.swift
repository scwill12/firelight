import Foundation

/// `GET /status` — the only call that works before sign-in.
///
/// Verified against `server/Server.js`: the body carries `app`,
/// `serverVersion`, `isInit`, `language`, `authMethods` and `authFormData`
/// (plus `ConfigPath`/`MetadataPath` while the server is uninitialised).
/// `authFormData` is left undecoded until a phase needs it — its shape depends
/// on which auth providers are configured.
public struct ServerStatus: Sendable, Hashable, Codable {
    public let app: String?
    public let serverVersion: String?
    public let isInit: Bool?
    public let language: String?
    /// e.g. `["local"]`, or `["local", "openid"]` when OIDC is configured.
    public let authMethods: [String]?

    public init(
        app: String? = nil,
        serverVersion: String? = nil,
        isInit: Bool? = nil,
        language: String? = nil,
        authMethods: [String]? = nil
    ) {
        self.app = app
        self.serverVersion = serverVersion
        self.isInit = isInit
        self.language = language
        self.authMethods = authMethods
    }

    public var version: ServerVersion? {
        serverVersion.flatMap(ServerVersion.init)
    }

    /// True when this really looks like an Audiobookshelf server rather than
    /// some other service answering on the same address.
    public var looksLikeAudiobookshelf: Bool {
        app?.lowercased() == "audiobookshelf" || serverVersion != nil
    }

    public var supportsOpenIDConnect: Bool {
        authMethods?.contains("openid") ?? false
    }

    public var featureTable: FeatureTable {
        FeatureTable(serverVersion: version)
    }
}

/// The ABS user object, as returned by `user.toOldJSONForBrowser()`.
///
/// Both `POST /login` (nested under `user`) and `GET /api/me` return this
/// shape. Only the fields Phase 0 needs are decoded; later phases add
/// `mediaProgress`, `bookmarks` and `permissions` as they implement them.
public struct ABSUser: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let username: String
    /// `root`, `admin`, `user` or `guest`.
    public let type: String?
    /// The legacy long-lived token, on servers that still issue one.
    public let token: String?
    /// Short-lived JWT. Always present on a 2.26+ login response.
    public let accessToken: String?
    /// Only present when the client sent `x-return-tokens: true`; otherwise ABS
    /// puts it in an http-only cookie, which a native client cannot rely on.
    public let refreshToken: String?

    public init(
        id: String,
        username: String,
        type: String? = nil,
        token: String? = nil,
        accessToken: String? = nil,
        refreshToken: String? = nil
    ) {
        self.id = id
        self.username = username
        self.type = type
        self.token = token
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public var isAdmin: Bool { type == "admin" || type == "root" }

    /// The token to send as `Authorization: Bearer`, preferring the modern one.
    public var bearerToken: String? { accessToken ?? token }
}

/// `POST /login` and `POST /auth/refresh` response.
///
/// Verified against `server/Auth.js` (`getUserLoginResponsePayload`): top-level
/// keys are `user`, `userDefaultLibraryId`, `serverSettings`, `ereaderDevices`
/// and `Source` — note the capital S on `Source`.
public struct LoginResponse: Sendable, Hashable, Codable {
    public let user: ABSUser
    public let userDefaultLibraryId: String?

    public init(user: ABSUser, userDefaultLibraryId: String? = nil) {
        self.user = user
        self.userDefaultLibraryId = userDefaultLibraryId
    }
}
