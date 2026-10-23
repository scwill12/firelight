import Foundation

/// One HTTP call, described independently of how it is sent, so tests can read
/// a request without a server and the mock server can answer one without URLSession.
public struct HTTPRequest: Sendable, Hashable {
    public enum Method: String, Sendable, Hashable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case put = "PUT"
        case delete = "DELETE"
    }

    public var method: Method
    /// Path relative to the server's base URL, e.g. `/api/libraries`. Leading
    /// slash optional; the base URL's own sub-path is always preserved.
    public var path: String
    public var query: [URLQueryItem]
    /// Headers for this one call. The per-server custom headers are added by the
    /// client, and these win on a name collision.
    public var headers: [String: String]
    public var body: Data?
    /// Whether to attach `Authorization: Bearer <accessToken>`.
    public var requiresAuth: Bool
    /// Whether a 401 should trigger one token refresh and one retry. Off for the
    /// auth calls themselves, so a failed refresh can't recurse.
    public var retriesAfterTokenRefresh: Bool

    public init(
        method: Method = .get,
        path: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        requiresAuth: Bool = true,
        retriesAfterTokenRefresh: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
        self.requiresAuth = requiresAuth
        self.retriesAfterTokenRefresh = retriesAfterTokenRefresh
    }

    /// A description safe to log: no query values, no headers, no host.
    public var redactedDescription: String {
        "\(method.rawValue) \(path)"
    }
}

public struct HTTPResponse: Sendable, Hashable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(status) }
}

/// The seam every feature talks to, and the one tests replace.
public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Supplies the current access token and knows how to renew it.
/// Implemented by the auth store in Phase 1.
public protocol AccessTokenProviding: Sendable {
    func accessToken() async -> String?
    /// Returns a new access token, or `nil` when the session can't be renewed
    /// and the user has to sign in again.
    func refreshAccessToken() async throws -> String?
}

/// Supplies the per-server custom headers a reverse proxy needs
/// (Cloudflare Access, Authelia, Authentik and similar).
public protocol CustomHeaderProviding: Sendable {
    func customHeaders() async -> [String: String]
}

/// A fixed set of custom headers, for tests and for servers behind no proxy.
public struct StaticCustomHeaders: CustomHeaderProviding {
    private let headers: [String: String]
    public init(_ headers: [String: String] = [:]) { self.headers = headers }
    public func customHeaders() async -> [String: String] { headers }
}

public extension HTTPClient {
    /// Sends a request and decodes the body with ABS's conventions.
    func send<T: Decodable & Sendable>(_ request: HTTPRequest, decoding _: T.Type) async throws -> T {
        let response = try await send(request)
        do {
            return try ABSJSON.decoder.decode(T.self, from: response.body)
        } catch {
            throw APIError.decoding(context: request.redactedDescription)
        }
    }

    /// Sends a request whose response body is not needed.
    @discardableResult
    func send(ignoringBody request: HTTPRequest) async throws -> HTTPResponse {
        try await send(request)
    }
}

/// JSON coders configured for Audiobookshelf.
///
/// ABS timestamps (`createdAt`, `updatedAt`, `lastUpdate`) are epoch
/// milliseconds as numbers, not seconds and not ISO-8601 strings. Decoding
/// accepts an ISO-8601 string as well, because a few newer fields use one.
public enum ABSJSON {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let milliseconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }
            let text = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date")
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSince1970 * 1000)
        }
        return encoder
    }()
}
