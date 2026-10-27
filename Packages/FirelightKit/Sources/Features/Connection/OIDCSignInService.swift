import ABSKit
import AuthenticationServices
import Foundation

/// Runs the OpenID Connect sign-in in a system browser sheet.
///
/// The flow, verified against ABS's `OidcAuthStrategy`:
///  1. We generate a PKCE pair and a state, and open
///     `/auth/openid?response_type=code&redirect_uri=…&code_challenge=…`.
///  2. The provider sends the browser back to the *server's*
///     `/auth/openid/mobile-redirect`, which bounces to our app URL with
///     `code` and `state`.
///  3. We redeem the code ourselves at `/auth/openid/callback`, sending the
///     verifier. ABS treats a mobile flow as API-based, so the tokens come
///     back as JSON rather than cookies.
@MainActor
final class OIDCSignInService: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// Must be whitelisted verbatim in the server's "Mobile redirect URIs"
    /// setting. ABS matches exactly — there is no pattern matching.
    static let redirectURI = "firelight://oauth"
    static let callbackScheme = "firelight"

    struct Callback: Sendable {
        let code: String
        let state: String
        let codeVerifier: String
    }

    func authorize(baseURL: URL) async throws -> Callback {
        let pkce = PKCEPair()
        let state = PKCEPair.randomURLSafeString(byteCount: 16)

        guard let authorizationURL = ABSEndpoint.openIDAuthorizationURL(
            baseURL: baseURL,
            redirectURI: Self.redirectURI,
            pkce: pkce,
            state: state
        ) else {
            throw SessionError.openIDUnavailable
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: Self.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: SessionError.cancelled)
                } else {
                    continuation.resume(throwing: SessionError.openIDFailed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: SessionError.openIDFailed)
            }
        }

        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let returnedState = items.first(where: { $0.name == "state" })?.value
        else {
            throw SessionError.openIDFailed
        }
        // The state we get back must be the one we sent, or this is not our flow.
        guard returnedState == state else { throw SessionError.openIDStateMismatch }

        return Callback(code: code, state: returnedState, codeVerifier: pkce.verifier)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

#if os(iOS)
import UIKit
#endif

public enum SessionError: LocalizedError, Equatable {
    case invalidAddress
    case notAudiobookshelf
    case signInFailed(String)
    case openIDUnavailable
    case openIDFailed
    case openIDStateMismatch
    case cancelled
    case storeUnavailable
    /// Signed in from an invitation, but the temporary password is still the
    /// account's password — so the code that carried it is still live.
    case passwordNotChanged

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "That doesn't look like a server address."
        case .notAudiobookshelf:
            "That address answered, but it isn't an Audiobookshelf server."
        case .signInFailed(let message):
            message
        case .openIDUnavailable:
            "This server isn't set up for single sign-on."
        case .openIDFailed:
            "Single sign-on didn't complete."
        case .openIDStateMismatch:
            "Single sign-on returned an unexpected response and was stopped."
        case .cancelled:
            "Sign-in was cancelled."
        case .storeUnavailable:
            "Firelight couldn't open its database."
        case .passwordNotChanged:
            """
            You're signed in, but your password wasn't changed, so the \
            invitation you were sent still works. Change your password in \
            your server's web interface.
            """
        }
    }
}
