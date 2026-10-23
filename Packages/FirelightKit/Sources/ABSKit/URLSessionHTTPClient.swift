import Foundation

/// The production `HTTPClient`: one per connected server address.
///
/// Responsibilities, in order of how much they matter:
///  1. Preserve the server's base sub-path when building URLs.
///  2. Attach the per-server custom headers on *every* request.
///  3. Attach `Authorization: Bearer`, and on a 401 refresh once and retry once.
///  4. Turn transport and status failures into `APIError`.
public final class URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokens: AccessTokenProviding?
    private let customHeaders: CustomHeaderProviding
    private let userAgent: String

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        tokens: AccessTokenProviding? = nil,
        customHeaders: CustomHeaderProviding = StaticCustomHeaders(),
        userAgent: String = URLSessionHTTPClient.defaultUserAgent
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
        self.customHeaders = customHeaders
        self.userAgent = userAgent
    }

    public static let defaultUserAgent = "Firelight/\(Bundle.main.shortVersion) (Audiobookshelf client)"

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let response = try await perform(request, token: await tokens?.accessToken())

        guard response.status == 401,
              request.requiresAuth,
              request.retriesAfterTokenRefresh,
              let tokens
        else {
            return try validate(response, for: request)
        }

        // One refresh, one retry. A second 401 means sign in again.
        let refreshed: String?
        do {
            refreshed = try await tokens.refreshAccessToken()
        } catch {
            throw APIError.unauthorized
        }
        guard let refreshed else { throw APIError.unauthorized }
        let retried = try await perform(request, token: refreshed)
        if retried.status == 401 { throw APIError.unauthorized }
        return try validate(retried, for: request)
    }

    // MARK: - Request building

    private func perform(_ request: HTTPRequest, token: String?) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: try makeURL(for: request))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Proxy headers first, so a per-call header and our own auth header both
        // take precedence over whatever the user configured.
        for (name, value) in await customHeaders.customHeaders() {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if request.requiresAuth, let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.decoding(context: request.redactedDescription)
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key.lowercased()] = value
                }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw Self.mapped(error)
        } catch {
            throw APIError.unreachable(underlying: String(describing: type(of: error)))
        }
    }

    func makeURL(for request: HTTPRequest) throws -> URL {
        let relative = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        let appended = relative.isEmpty ? baseURL : baseURL.appending(path: relative)
        guard var components = URLComponents(url: appended, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    // MARK: - Failure mapping

    private func validate(_ response: HTTPResponse, for request: HTTPRequest) throws -> HTTPResponse {
        if response.isSuccess { return response }
        switch response.status {
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 429:
            let retryAfter = response.headers["retry-after"].flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        default:
            throw APIError.server(status: response.status, message: Self.message(from: response.body))
        }
    }

    /// ABS errors come back either as `{"error": "..."}` or as a bare string.
    /// Anything longer than a sentence is dropped rather than shown to a user.
    static func message(from body: Data) -> String? {
        guard !body.isEmpty, body.count < 4096 else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            for key in ["error", "message"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
            }
            return nil
        }
        guard let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 200, !text.hasPrefix("<")
        else { return nil }
        return text
    }

    static func mapped(_ error: URLError) -> APIError {
        switch error.code {
        case .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .secureConnectionFailed:
            return .untrustedCertificate(fingerprint: nil)
        case .cancelled:
            return .unreachable(underlying: "cancelled")
        default:
            return .unreachable(underlying: error.code.rawValue.description)
        }
    }
}

public extension Bundle {
    /// The app's marketing version, used in the user agent and in the device
    /// info sent when opening a playback session.
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
