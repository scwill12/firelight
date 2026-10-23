import Foundation

/// One Audiobookshelf server as the user configured it.
///
/// Credentials, custom headers and trusted certificates are *not* stored here —
/// they live in the shared Keychain, keyed by `id`. This type is safe to put in
/// SwiftData, a log line or a diagnostics export.
public struct ServerDescriptor: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    /// What the user calls this server. Never an address.
    public var displayName: String
    /// The address to prefer when it answers — typically a LAN address.
    public var localURL: URL?
    /// The address that works from anywhere.
    public var remoteURL: URL
    /// Set once the user has explicitly trusted a self-signed certificate.
    public var trustedCertificate: CertificateFingerprint?

    public init(
        id: UUID = UUID(),
        displayName: String,
        localURL: URL? = nil,
        remoteURL: URL,
        trustedCertificate: CertificateFingerprint? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.trustedCertificate = trustedCertificate
    }

    /// Both addresses, local first, for the reachability probe to race.
    public var candidateURLs: [URL] {
        if let localURL, localURL != remoteURL { return [localURL, remoteURL] }
        return [remoteURL]
    }
}

/// Which of a server's addresses is in use right now.
public enum ActiveAddress: String, Sendable, Hashable, Codable {
    case local
    case remote
}

/// Normalises what a user types into a base URL we can append paths to.
///
/// ABS can be hosted under a sub-path (`RouterBasePath`, e.g.
/// `https://example.com/audiobookshelf`), so the path a user pastes has to be
/// preserved — only a trailing slash and a pasted `/login` are dropped.
public enum ServerURLParser {
    /// What the address fields are prefilled with. Self-hosted servers are
    /// overwhelmingly https, and typing it is the most tedious part of the
    /// only screen a new user cannot skip.
    public static let defaultScheme = "https://"

    /// True when the text does not name a host yet.
    ///
    /// Prefilling `https://` means an untouched field is no longer empty, so
    /// "has the user typed an address?" can no longer be `isEmpty`. Anything
    /// that is only the beginning of a scheme counts as blank, which also
    /// keeps the live reachability check from probing while someone is still
    /// typing. A single-label LAN name is unaffected: `nas` is not a prefix of
    /// either scheme, so it reads as an address immediately.
    public static func isBlank(_ input: String) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let lowered = text.lowercased()
        return "https://".hasPrefix(lowered) || "http://".hasPrefix(lowered)
    }

    public static func parse(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil

        var path = components.path
        for suffix in ["/login", "/library", "/audiobookshelf/login"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
            break
        }
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path

        return components.url
    }
}
