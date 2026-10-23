import CryptoKit
import Foundation

/// Proof Key for Code Exchange, for the OpenID Connect sign-in flow.
///
/// ABS requires `code_challenge` on the mobile flow and refuses the request
/// without it. The server never sees the verifier until the callback, and never
/// stores it — the app keeps it for the length of one sign-in.
public struct PKCEPair: Sendable, Hashable {
    /// The secret the app keeps and sends only on the final callback.
    public let verifier: String
    /// `base64url(SHA256(verifier))`, sent when starting the flow.
    public let challenge: String
    /// ABS accepts only `S256`.
    public let method = "S256"

    public init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(digest).base64URLEncodedString()
    }

    /// A fresh pair with a 64-character verifier, well inside RFC 7636's
    /// 43–128 range.
    public init() {
        self.init(verifier: Self.randomURLSafeString(byteCount: 48))
    }

    /// Also used for the OAuth `state` parameter.
    public static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            // SecRandom does not fail in practice; if it ever does, a UUID-based
            // value is still unguessable enough to be safe here.
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64URLEncodedString()
    }
}

public extension Data {
    /// base64url without padding, per RFC 4648 §5 — what OAuth expects.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
