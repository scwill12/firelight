import CryptoKit
import Foundation

/// The SHA-256 of a certificate's DER bytes — what the user is shown before
/// they trust a self-signed server, and what we pin afterwards.
public struct CertificateFingerprint: Sendable, Hashable, Codable, CustomStringConvertible {
    public let sha256: Data

    public init(sha256: Data) { self.sha256 = sha256 }

    public init(certificate: SecCertificate) {
        let der = SecCertificateCopyData(certificate) as Data
        self.sha256 = Data(SHA256.hash(data: der))
    }

    /// Colon-separated hex, one byte per group — the format `openssl` and
    /// every browser use, so a user can compare it against their server by eye.
    public var description: String {
        sha256.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// Answers "has the user trusted this host's certificate, and which one?"
public protocol TrustedCertificateStore: Sendable {
    func trustedFingerprint(forHost host: String) async -> CertificateFingerprint?
    /// Called when a host presents a certificate the system rejected, so
    /// onboarding can show the user what they would be trusting.
    func recordRejected(_ fingerprint: CertificateFingerprint, forHost host: String) async
}

/// In-memory trust store. Phase 1 persists the trusted set to the Keychain and
/// keeps this as the cache in front of it.
public actor CertificateTrustCoordinator: TrustedCertificateStore {
    private var trusted: [String: CertificateFingerprint]
    private var lastRejected: [String: CertificateFingerprint] = [:]

    public init(trusted: [String: CertificateFingerprint] = [:]) {
        self.trusted = trusted
    }

    public func trustedFingerprint(forHost host: String) async -> CertificateFingerprint? {
        trusted[host.lowercased()]
    }

    public func recordRejected(_ fingerprint: CertificateFingerprint, forHost host: String) async {
        lastRejected[host.lowercased()] = fingerprint
    }

    /// What onboarding shows the user when a TLS handshake was refused.
    public func rejectedFingerprint(forHost host: String) -> CertificateFingerprint? {
        lastRejected[host.lowercased()]
    }

    public func trust(_ fingerprint: CertificateFingerprint, forHost host: String) {
        trusted[host.lowercased()] = fingerprint
    }

    /// Trusts the certificate this host most recently presented and had
    /// rejected — which is the decision the user is actually making when they
    /// tap "Trust this certificate" next to a fingerprint.
    @discardableResult
    public func trustRejected(forHost host: String) -> Bool {
        guard let fingerprint = lastRejected[host.lowercased()] else { return false }
        trusted[host.lowercased()] = fingerprint
        return true
    }

    public func revokeTrust(forHost host: String) {
        trusted[host.lowercased()] = nil
    }
}

/// Accepts a self-signed certificate only when its fingerprint is the exact one
/// the user trusted for that host. Everything else falls through to the system,
/// so a genuinely invalid certificate still fails and a CA-signed one still
/// succeeds. Validation is never disabled globally.
public final class PinnedCertificateSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let store: TrustedCertificateStore

    public init(store: TrustedCertificateStore) {
        self.store = store
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let fingerprint = CertificateFingerprint(certificate: leaf)
        let store = self.store

        Task {
            if await store.trustedFingerprint(forHost: host) == fingerprint {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            // Not pinned: let the system decide, and remember what was offered
            // so the user can be shown the fingerprint if it was rejected.
            if !Self.systemTrusts(trust) {
                await store.recordRejected(fingerprint, forHost: host)
            }
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private static func systemTrusts(_ trust: SecTrust) -> Bool {
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }
}
