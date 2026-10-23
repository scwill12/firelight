import ABSKit
import Foundation

/// What the live connection check found, as the onboarding screen shows it.
public enum ConnectionCheckResult: Sendable, Equatable {
    case checking
    /// Reachable and really Audiobookshelf.
    case reachable(version: String?, authMethods: [String], address: ActiveAddress)
    /// TLS failed. The fingerprint is what the user is asked to trust.
    case untrustedCertificate(fingerprint: String?, host: String)
    /// Something answered, but it isn't an ABS server.
    case notAudiobookshelf
    case unreachable
    case failed(message: String)

    public var isReachable: Bool {
        if case .reachable = self { return true }
        return false
    }

    public var supportsOpenID: Bool {
        if case .reachable(_, let methods, _) = self { return methods.contains("openid") }
        return false
    }
}

/// Runs the check. Separate from the view so it can be exercised without one.
@MainActor
struct ConnectionChecker {
    let factory: ConnectionFactory

    func check(urlText: String, headers: [String: String] = [:]) async -> ConnectionCheckResult {
        guard let url = ServerURLParser.parse(urlText) else {
            return .failed(message: "That doesn't look like a server address.")
        }
        return await check(url: url, headers: headers)
    }

    func check(url: URL, headers: [String: String] = [:]) async -> ConnectionCheckResult {
        do {
            let status = try await factory
                .anonymousClient(baseURL: url, headers: StaticCustomHeaders(headers))
                .status()
            guard status.looksLikeAudiobookshelf else { return .notAudiobookshelf }
            return .reachable(
                version: status.serverVersion,
                authMethods: status.authMethods ?? ["local"],
                address: .remote
            )
        } catch let error as APIError {
            switch error {
            case .untrustedCertificate:
                let host = url.host() ?? ""
                let fingerprint = await factory.trust.rejectedFingerprint(forHost: host)
                return .untrustedCertificate(fingerprint: fingerprint?.description, host: host)
            case .unreachable:
                return .unreachable
            case .notFound:
                return .notAudiobookshelf
            default:
                return .failed(message: error.localizedDescription)
            }
        } catch {
            return .unreachable
        }
    }
}
