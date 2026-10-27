import Foundation

/// An invitation to one Audiobookshelf account, as it travels in a code.
///
/// Four things, and no more: every field here is characters somebody has to
/// paste. The server's name and the person's own name are **not** carried —
/// they are read from the server once the code has been redeemed, which makes
/// the code a third shorter and the greeting more accurate than anything the
/// admin could have typed.
///
/// The password is a **temporary** one the admin never sees. It exists only so
/// the first request can authenticate; the invitation screen immediately
/// replaces it with one the invited person chooses, and Audiobookshelf
/// invalidates every other session for the account when it does. A redeemed
/// code is a spent match.
///
/// The limit is worth stating plainly: between sending and redeeming, this
/// code *is* the account. Whoever reads it first gets in, and the person it
/// was meant for then finds their password already changed — which is at
/// least loud rather than silent.
public struct Invite: Sendable, Hashable, Codable {
    public var serverURL: URL
    public var username: String
    public var temporaryPassword: String
    /// Enforced by the app, not the server. Audiobookshelf has no notion of
    /// an invitation, so a crafted request ignores this: it limits honest
    /// mistakes, not attackers.
    public var expiresAt: Date

    public init(
        serverURL: URL,
        username: String,
        temporaryPassword: String,
        expiresAt: Date
    ) {
        self.serverURL = serverURL
        self.username = username
        self.temporaryPassword = temporaryPassword
        self.expiresAt = expiresAt
    }

    public func hasExpired(now: Date = .now) -> Bool { now > expiresAt }
}

/// Turns an invitation into something you can paste into a message, and back.
///
/// Not a link. A tappable `https://` link needs a domain to host its landing
/// page, and a client for self-hosted servers has no business routing
/// invitations through its author's website — even a static page that
/// receives nothing. A code needs no infrastructure, cannot rot when a site
/// moves, and names nobody's server but the one it is for.
///
/// The cost is one extra step, and it is nearly free: the message has to say
/// "install Firelight" either way, so "install Firelight and paste this" is
/// the same instruction.
///
/// The payload is base64url of compact JSON. That is **encoding, not
/// encryption** — whoever holds the code holds the credential until it is
/// redeemed. Compression was tried and removed: at this size zlib saved three
/// characters and added a way to fail.
public enum InviteCode {
    /// Marks the format, so a later one can be told apart and a stray paste
    /// is recognisable as an invitation rather than nonsense.
    public static let prefix = "FL1"

    public static func make(from invite: Invite) throws -> String {
        prefix + base64url(try JSONEncoder().encode(Payload(invite)))
    }

    public static func invite(from code: String) throws -> Invite {
        // Messages wrap, people add spaces, and a code dictated over the
        // phone arrives with whatever the listener typed.
        let cleaned = code.filter { !$0.isWhitespace }
        guard cleaned.hasPrefix(prefix) else { throw InviteError.notAnInvite }

        let body = String(cleaned.dropFirst(prefix.count))
        guard !body.isEmpty, let data = data(fromBase64url: body) else {
            throw InviteError.malformed
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw InviteError.malformed
        }
        return try payload.invite()
    }

    /// Single-letter keys, because every byte is a character to paste. The
    /// readable names live on `Invite`, where they are read.
    private struct Payload: Codable {
        let u: String   // server URL
        let n: String   // username
        let p: String   // temporary password
        let e: Int      // expiry, epoch seconds

        init(_ invite: Invite) {
            u = invite.serverURL.absoluteString
            n = invite.username
            p = invite.temporaryPassword
            e = Int(invite.expiresAt.timeIntervalSince1970)
        }

        func invite() throws -> Invite {
            guard let url = URL(string: u), url.scheme != nil, url.host() != nil,
                  !n.isEmpty, !p.isEmpty
            else { throw InviteError.malformed }
            return Invite(
                serverURL: url,
                username: n,
                temporaryPassword: p,
                expiresAt: Date(timeIntervalSince1970: TimeInterval(e))
            )
        }
    }

    // MARK: - base64url

    /// Standard base64 uses `+` and `/`, which a messaging app may mangle if
    /// it decides a code looks like a URL, and `=` padding that readers
    /// disagree about. RFC 4648's URL alphabet avoids all three.
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

/// Makes the temporary password that only ever travels in the code.
public enum TemporaryPassword {
    /// Unambiguous characters only. This is never typed by a person on
    /// purpose, but a code does sometimes get read aloud when a paste fails.
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// Sixteen characters of a 31-letter alphabet is about 79 bits, which is
    /// far more than something that dies on first use needs — and twenty-four
    /// made the code visibly longer for no gain.
    public static func make(length: Int = 16) -> String {
        String((0..<max(length, 12)).map { _ in
            alphabet[Int.random(in: 0..<alphabet.count)]
        })
    }
}
