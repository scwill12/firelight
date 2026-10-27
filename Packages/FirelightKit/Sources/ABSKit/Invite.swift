import Foundation

/// An invitation to one Audiobookshelf account, as it travels in a link.
///
/// The password here is a **temporary** one the admin never tells anyone. It
/// exists only so the invited person's first request can authenticate; the
/// redemption screen immediately replaces it with one they choose, and
/// Audiobookshelf invalidates every other session for the account when it
/// does. A link that has been redeemed is a spent match.
///
/// That is the whole security model, and it is worth being plain about its
/// limit: between sending and redeeming, this link *is* the account. Anyone
/// who reads it first gets in, and the person it was meant for then finds
/// their password already changed — which is at least loud rather than silent.
public struct Invite: Sendable, Hashable, Codable {
    /// The server to sign in to.
    public var serverURL: URL
    /// What to call the server on screen, so the invitation names something
    /// the person recognises rather than an address.
    public var serverName: String
    /// The account that was created for them.
    public var username: String
    /// What to greet them as. Often the same as `username`, not always.
    public var displayName: String
    /// Valid only until the first password is set; see the type's note.
    public var temporaryPassword: String
    /// When this stops being offered. Enforced by the app, not the server —
    /// Audiobookshelf has no notion of an invitation, so a crafted request
    /// ignores this. It limits honest mistakes, not attackers.
    public var expiresAt: Date

    public init(
        serverURL: URL,
        serverName: String,
        username: String,
        displayName: String,
        temporaryPassword: String,
        expiresAt: Date
    ) {
        self.serverURL = serverURL
        self.serverName = serverName
        self.username = username
        self.displayName = displayName
        self.temporaryPassword = temporaryPassword
        self.expiresAt = expiresAt
    }

    public func hasExpired(now: Date = .now) -> Bool { now > expiresAt }
}

/// Puts an invitation into a link and takes it out again.
///
/// The link is an ordinary `https://` one, so it is clickable everywhere, it
/// renders as a titled card rather than a wall of characters, and it still
/// does something useful when Firelight is not installed — the page it points
/// at offers the App Store.
///
/// **The payload lives in the fragment, and that is a security decision, not
/// a formatting one.** Everything after `#` is never sent to a server. A
/// query string would be: iMessage, Slack, WhatsApp and the rest all fetch
/// links to build their previews, so a credential in the query would be
/// handed to every one of those companies before the recipient ever taps it.
/// In the fragment, the preview bot fetches a page that knows nothing.
///
/// The encoding is base64url, which is **not encryption**. Whoever holds the
/// link holds the credential until it is redeemed.
public enum InviteLink {
    /// The page that greets someone without the app. Lives on GitHub Pages;
    /// `Invite.md` in the docs folder says what it has to serve.
    public static let webHost = "scwill12.github.io"
    public static let webPath = "/firelight/join"

    /// Kept for testing and for a device that has the app but no association
    /// yet. Links sent to people are always the `https` form.
    public static let scheme = "firelight"
    public static let host = "invite"

    public static func url(for invite: Invite) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = webHost
        components.path = webPath
        components.fragment = base64url(try JSONEncoder().encode(invite))
        guard let url = components.url else { throw InviteError.malformed }
        return url
    }

    public static func invite(from url: URL) throws -> Invite {
        guard let encoded = payload(in: url) else { throw InviteError.notAnInvite }
        guard let data = data(fromBase64url: encoded) else { throw InviteError.malformed }
        return try JSONDecoder().decode(Invite.self, from: data)
    }

    /// Accepts either form: the web link people are sent, or the custom
    /// scheme, which is how this is exercised before the domain association
    /// is in place.
    private static func payload(in url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if url.scheme?.lowercased() == "https",
           url.host()?.lowercased() == webHost,
           url.path() == webPath,
           let fragment = components?.fragment, !fragment.isEmpty {
            return fragment
        }
        if url.scheme?.lowercased() == scheme, url.host()?.lowercased() == host {
            if let fragment = components?.fragment, !fragment.isEmpty { return fragment }
            return components?.queryItems?.first { $0.name == "d" }?.value.flatMap {
                $0.isEmpty ? nil : $0
            }
        }
        return nil
    }

    // MARK: - base64url

    /// Standard base64 uses `+` and `/`, which a URL has its own uses for, and
    /// `=` padding that readers disagree about. RFC 4648's URL alphabet
    /// avoids all three.
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(fromBase64url text: String) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Put back the padding the URL form drops.
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}

public enum InviteError: Error, Sendable, Equatable {
    case notAnInvite
    case malformed
    case expired
}

/// Makes the temporary password that only ever travels in the link.
public enum TemporaryPassword {
    /// Unambiguous characters only: this is never typed by a person, but it
    /// may well be read aloud or copied by hand when a link fails.
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    public static func make(length: Int = 24) -> String {
        String((0..<max(length, 12)).map { _ in
            alphabet[Int.random(in: 0..<alphabet.count)]
        })
    }
}
