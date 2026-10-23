import Foundation

/// Features that need a minimum Audiobookshelf version, and the version each
/// one needs.
///
/// Working rule 8 of the spec: anything that depends on a newer ABS version is
/// gated here and degrades with a clear message, never a crash or a silent
/// failure. Add an entry before writing the call, not after a user reports it.
///
/// Every version below is taken from the ABS source or its release notes. When
/// a minimum is not yet confirmed, leave the feature out of the table rather
/// than guessing: an absent entry means "assume supported", and a wrong
/// minimum silently hides a feature that works.
public enum ABSFeature: String, Sendable, CaseIterable, Codable {
    /// JWT access tokens with `POST /auth/refresh`. ABS 2.26.0 replaced the
    /// long-lived `user.token` with this; the legacy token still works on
    /// servers that have not removed it.
    case refreshTokenAuth

    /// `x-return-tokens: true` on `POST /login`, which puts the refresh token in
    /// the response body instead of an http-only cookie. Required for a native
    /// client: we have no cookie jar we want to depend on. Shipped with the
    /// 2.26.0 auth rework.
    case tokensInLoginResponseBody

    /// `GET /api/api-keys` and friends, for clients that authenticate with a
    /// long-lived API key rather than a password.
    case apiKeys

    public var minimumVersion: ServerVersion {
        switch self {
        case .refreshTokenAuth: ServerVersion(major: 2, minor: 26, patch: 0)
        case .tokensInLoginResponseBody: ServerVersion(major: 2, minor: 26, patch: 0)
        case .apiKeys: ServerVersion(major: 2, minor: 26, patch: 0)
        }
    }

    /// Shown to the user when the feature is gated off.
    public var displayName: String {
        switch self {
        case .refreshTokenAuth: "Staying signed in"
        case .tokensInLoginResponseBody: "Staying signed in"
        case .apiKeys: "API key sign-in"
        }
    }
}

/// Answers "can this server do X?" for one connected server.
public struct FeatureTable: Sendable, Hashable, Codable {
    /// `nil` when the server version is not known yet. An unknown version is
    /// treated as "too old" for gated features, so we never send a call the
    /// server cannot answer.
    public let serverVersion: ServerVersion?

    public init(serverVersion: ServerVersion?) {
        self.serverVersion = serverVersion
    }

    public func supports(_ feature: ABSFeature) -> Bool {
        guard let serverVersion else { return false }
        return serverVersion >= feature.minimumVersion
    }

    /// Throws the error a feature should surface when the server is too old,
    /// so call sites read as `try table.require(.apiKeys)`.
    public func require(_ feature: ABSFeature) throws {
        guard supports(feature) else {
            throw APIError.unsupportedByServer(
                feature: feature.displayName,
                required: feature.minimumVersion,
                actual: serverVersion
            )
        }
    }

    public var unsupportedFeatures: [ABSFeature] {
        ABSFeature.allCases.filter { !supports($0) }
    }
}
