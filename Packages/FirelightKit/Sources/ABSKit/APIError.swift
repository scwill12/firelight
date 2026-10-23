import Foundation

/// Every failure the API layer can produce, in terms a feature can act on.
///
/// Error descriptions are shown to users and written to the diagnostics export,
/// so none of them may carry a token, a password or a full server URL. Hosts are
/// redacted by `Redaction` before they reach a message.
public enum APIError: Error, Sendable, Equatable {
    /// The request could not be turned into a valid URL.
    case invalidURL
    /// No network path to the server, or the request timed out.
    case unreachable(underlying: String)
    /// TLS failed and the user has not trusted this server's certificate.
    case untrustedCertificate(fingerprint: String?)
    /// 401 after a token refresh was attempted. The user must sign in again.
    case unauthorized
    /// 403. The signed-in user lacks permission for this call.
    case forbidden
    /// 404.
    case notFound
    /// 429, with the server's retry hint when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other non-2xx status.
    case server(status: Int, message: String?)
    /// A 2xx body that did not match the expected shape.
    case decoding(context: String)
    /// The server is older than the minimum version this feature needs.
    case unsupportedByServer(feature: String, required: ServerVersion, actual: ServerVersion?)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "That server address isn't valid."
        case .unreachable:
            return "Can't reach the server."
        case .untrustedCertificate:
            return "This server's certificate isn't trusted."
        case .unauthorized:
            return "Your sign-in has expired."
        case .forbidden:
            return "Your account doesn't have permission to do that."
        case .notFound:
            return "The server couldn't find that."
        case .rateLimited:
            return "The server is asking us to slow down."
        case .server(let status, let message):
            return message ?? "The server returned an error (\(status))."
        case .decoding:
            return "The server sent a response Firelight didn't understand."
        case .unsupportedByServer(let feature, let required, _):
            return "\(feature) needs Audiobookshelf \(required) or newer."
        }
    }

    /// Whether retrying the identical request could plausibly succeed.
    public var isTransient: Bool {
        switch self {
        case .unreachable, .rateLimited: return true
        case .server(let status, _): return status >= 500
        default: return false
        }
    }
}
