import ABSKit
import Foundation

/// A stand-in Audiobookshelf server for tests.
///
/// It answers over `URLProtocol` rather than exposing a fake `HTTPClient`, so a
/// test exercises the production stack end to end: URL building (including a
/// server hosted under a sub-path), the per-server custom headers, the bearer
/// token, the 401-refresh-retry, and the real decoders.
///
/// Routes and payload shapes follow the ABS source — see the verified route
/// table in CLAUDE.md. Each instance gets its own host, so tests can run in
/// parallel.
public final class MockABSServer: @unchecked Sendable {
    /// Scenarios a test can ask the server to be in.
    public struct Behaviour: Sendable {
        /// Reject the current access token, forcing a refresh.
        public var accessTokenIsExpired = false
        /// Reject refresh too, which should surface as `.unauthorized`.
        public var refreshTokenIsRejected = false
        /// Fail every request with this status until cleared.
        public var failEverythingWith: Int?
        /// A header the server insists on, as a reverse proxy would.
        public var requiredHeader: (name: String, value: String)?
        public init() {}
    }

    private let lock = NSLock()
    private var _behaviour = Behaviour()
    private var _requestLog: [RecordedRequest] = []
    private var _accessToken = "access-token-1"
    private var _refreshToken = "refresh-token-1"
    private var _tokenGeneration = 1
    private var _localSessions: [[String: Any]] = []
    private var _progressUpdates: [[String: Any]] = []
    private var _mediaProgress: [[String: Any]] = []

    public let host: String
    /// The sub-path the server is hosted under, e.g. `/abs`. Empty for root.
    public let basePath: String
    public let serverVersion: String
    public let username: String
    public let password: String
    public let userID: String

    public init(
        serverVersion: String = "2.26.0",
        basePath: String = "",
        username: String = "cole",
        password: String = "correct-horse",
        userID: String = "usr-1"
    ) {
        self.host = "mock-\(UUID().uuidString.prefix(8).lowercased()).firelight.test"
        self.basePath = basePath
        self.serverVersion = serverVersion
        self.username = username
        self.password = password
        self.userID = userID
        MockRegistry.shared.register(self, forHost: host)
    }

    deinit {
        MockRegistry.shared.unregister(host: host)
    }

    /// The base URL to hand `URLSessionHTTPClient`.
    public var baseURL: URL {
        URL(string: "https://\(host)\(basePath)")!
    }

    /// A session wired to this server and nothing else.
    public var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockABSURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A ready-made client for this server.
    public func makeClient(
        tokens: AccessTokenProviding? = nil,
        customHeaders: CustomHeaderProviding = StaticCustomHeaders()
    ) -> ABSClient {
        ABSClient(
            http: URLSessionHTTPClient(
                baseURL: baseURL,
                session: session,
                tokens: tokens,
                customHeaders: customHeaders
            )
        )
    }

    // MARK: - Test control

    public var behaviour: Behaviour {
        get { lock.withLock { _behaviour } }
        set { lock.withLock { _behaviour = newValue } }
    }

    public var currentAccessToken: String { lock.withLock { _accessToken } }
    public var currentRefreshToken: String { lock.withLock { _refreshToken } }

    /// Every request the server received, in order.
    public var requestLog: [RecordedRequest] { lock.withLock { _requestLog } }

    public func clearRequestLog() {
        lock.withLock { _requestLog.removeAll() }
    }

    public func requests(matching path: String) -> [RecordedRequest] {
        requestLog.filter { $0.path == path }
    }

    /// Offline sessions the client has reported.
    public var localSessions: [[String: Any]] { lock.withLock { _localSessions } }
    /// Progress writes the client has made.
    public var progressUpdates: [[String: Any]] { lock.withLock { _progressUpdates } }

    /// Seeds what `GET /api/me` reports, for reconciliation tests.
    public func setMediaProgress(_ progress: [[String: Any]]) {
        lock.withLock { _mediaProgress = progress }
    }

    // MARK: - Routing

    func respond(to request: RecordedRequest) -> MockHTTPResponse {
        lock.withLock { _requestLog.append(request) }

        if let status = behaviour.failEverythingWith {
            return .json(status: status, object: ["error": "Forced failure"])
        }

        if let required = behaviour.requiredHeader,
           request.header(required.name) != required.value {
            return .json(status: 403, object: ["error": "Missing proxy header"])
        }

        switch (request.method, request.path) {
        case ("GET", "/status"):
            return .json(status: 200, object: statusPayload())
        case ("GET", "/ping"):
            return .json(status: 200, object: ["success": true])
        case ("POST", "/login"):
            return login(request)
        case ("POST", "/auth/refresh"):
            return refresh(request)
        case ("POST", "/logout"):
            return .json(status: 200, object: ["success": true])
        case ("GET", "/api/me"):
            return authenticated(request) {
                var payload = self.userPayload(includeTokens: false)
                payload["mediaProgress"] = self.lock.withLock { self._mediaProgress }
                return .json(status: 200, object: payload)
            }
        case ("POST", "/api/session/local"), ("POST", "/api/session/local-all"):
            return authenticated(request) {
                self.lock.withLock { self._localSessions.append(request.jsonBody ?? [:]) }
                return MockHTTPResponse(status: 200, headers: [:], body: Data())
            }
        default:
            // Paths carrying ids need prefix matching.
            if request.method == "PATCH", request.path.hasPrefix("/api/me/progress/") {
                return authenticated(request) {
                    self.lock.withLock { self._progressUpdates.append(request.jsonBody ?? [:]) }
                    return MockHTTPResponse(status: 200, headers: [:], body: Data())
                }
            }
            if request.method == "GET", request.path.hasPrefix("/api/me/bookmarks/") {
                return authenticated(request) { .jsonArray(status: 200, array: []) }
            }
            return .json(status: 404, object: ["error": "Not found"])
        }
    }

    private func statusPayload() -> [String: Any] {
        [
            "app": "audiobookshelf",
            "serverVersion": serverVersion,
            "isInit": true,
            "language": "en-us",
            "authMethods": ["local"],
            "authFormData": [:],
        ]
    }

    private func userPayload(includeTokens: Bool, includeRefresh: Bool = false) -> [String: Any] {
        var user: [String: Any] = [
            "id": userID,
            "username": username,
            "type": "admin",
        ]
        if includeTokens {
            user["accessToken"] = lock.withLock { _accessToken }
            // ABS only returns the refresh token in the body when the client
            // sent `x-return-tokens: true`; otherwise it is cookie-only and the
            // field is null.
            user["refreshToken"] = includeRefresh ? lock.withLock { _refreshToken } : NSNull()
        }
        return user
    }

    private func loginPayload(includeRefresh: Bool) -> [String: Any] {
        [
            "user": userPayload(includeTokens: true, includeRefresh: includeRefresh),
            "userDefaultLibraryId": "lib-1",
            "serverSettings": [:],
            "ereaderDevices": [],
            "Source": "docker",
        ]
    }

    private func login(_ request: RecordedRequest) -> MockHTTPResponse {
        guard let body = request.jsonBody,
              body["username"] as? String == username,
              body["password"] as? String == password
        else {
            return .json(status: 401, object: ["error": "Invalid user or password"])
        }
        let returnTokens = request.header("x-return-tokens") == "true"
        return .json(status: 200, object: loginPayload(includeRefresh: returnTokens))
    }

    private func refresh(_ request: RecordedRequest) -> MockHTTPResponse {
        if behaviour.refreshTokenIsRejected {
            return .json(status: 401, object: ["error": "Refresh token is invalid"])
        }
        guard let offered = request.header("x-refresh-token"),
              offered == currentRefreshToken
        else {
            return .json(status: 401, object: ["error": "No refresh token provided"])
        }
        lock.withLock {
            _tokenGeneration += 1
            _accessToken = "access-token-\(_tokenGeneration)"
            _refreshToken = "refresh-token-\(_tokenGeneration)"
            _behaviour.accessTokenIsExpired = false
        }
        return .json(status: 200, object: loginPayload(includeRefresh: true))
    }

    private func authenticated(
        _ request: RecordedRequest,
        then body: () -> MockHTTPResponse
    ) -> MockHTTPResponse {
        guard let header = request.header("Authorization"),
              header == "Bearer \(currentAccessToken)",
              !behaviour.accessTokenIsExpired
        else {
            return .json(status: 401, object: ["error": "Unauthorized"])
        }
        return body()
    }
}

/// One request as the server saw it, for assertions.
public struct RecordedRequest: Sendable, Hashable {
    public let method: String
    /// Path with the server's base sub-path removed, so assertions read
    /// `/api/me` whether or not the server is hosted under `/abs`.
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, path: String, query: [String: String], headers: [String: String], body: Data?) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// Case-insensitive, because HTTP header names are.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }

    public var jsonBody: [String: Any]? {
        guard let body else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}

public struct MockHTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public static func jsonArray(status: Int, array: [Any]) -> MockHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: array)) ?? Data()
        return MockHTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: data)
    }

    public static func json(status: Int, object: [String: Any]) -> MockHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return MockHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }
}
