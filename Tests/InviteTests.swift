import Foundation
import Testing
@testable import ABSKit

@Suite("Invitation links")
struct InviteTests {
    private func sample(
        expiresIn: TimeInterval = 7 * 24 * 60 * 60,
        username: String = "sam"
    ) -> Invite {
        Invite(
            serverURL: URL(string: "https://books.example.com:13378/abs")!,
            serverName: "The Library",
            username: username,
            displayName: "Sam",
            temporaryPassword: "abcdefghjkmn",
            expiresAt: Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(expiresIn)
        )
    }

    @Test("An invitation survives the round trip through a link")
    func roundTrips() throws {
        let invite = sample()
        let url = try InviteLink.url(for: invite)
        #expect(try InviteLink.invite(from: url) == invite)
    }

    @Test("The server's own sub-path is preserved")
    func keepsTheSubPath() throws {
        // Audiobookshelf can live under a RouterBasePath; dropping it would
        // point the invited person at a server that is not there.
        let url = try InviteLink.url(for: sample())
        let decoded = try InviteLink.invite(from: url)
        #expect(decoded.serverURL.absoluteString == "https://books.example.com:13378/abs")
    }

    @Test("The password is not legible in the link")
    func passwordIsNotPlainText() throws {
        let url = try InviteLink.url(for: sample())
        // Encoding, not encryption — but a chat preview should not render
        // somebody's password as readable text beside their name.
        #expect(!url.absoluteString.contains("abcdefghjkmn"))
        #expect(!url.absoluteString.lowercased().contains("password"))
    }

    @Test("The link is an ordinary https one, so it works without the app")
    func isAWebLink() throws {
        let url = try InviteLink.url(for: sample())
        #expect(url.scheme == "https")
        #expect(url.host() == InviteLink.webHost)
        #expect(url.path() == InviteLink.webPath)
    }

    @Test("The payload is in the fragment, which never reaches a server")
    func payloadIsInTheFragment() throws {
        let url = try InviteLink.url(for: sample())
        // Link previews fetch the URL. A query string would hand the
        // credential to every preview service that saw the message.
        #expect(url.query() == nil)
        #expect(url.fragment() != nil)
    }

    @Test("The custom scheme still works, for testing before the domain is live")
    func acceptsTheCustomScheme() throws {
        let invite = sample()
        let encoded = InviteLink.base64url(try JSONEncoder().encode(invite))
        for form in ["firelight://invite#\(encoded)", "firelight://invite?d=\(encoded)"] {
            #expect(try InviteLink.invite(from: URL(string: form)!) == invite)
        }
    }

    @Test("A link for something else is refused, not misread")
    func refusesOtherLinks() {
        for other in ["https://example.com/invite#abc",
                      "https://\(InviteLink.webHost)/somewhere-else#abc",
                      "firelight://open?d=abc",
                      "otherapp://invite?d=abc"] {
            #expect(throws: InviteError.self) {
                try InviteLink.invite(from: URL(string: other)!)
            }
        }
    }

    @Test("A damaged payload is refused rather than half-read")
    func refusesDamagedPayloads() {
        for bad in ["firelight://invite",
                    "firelight://invite?d=",
                    "https://\(InviteLink.webHost)\(InviteLink.webPath)",
                    "https://\(InviteLink.webHost)\(InviteLink.webPath)#YWJj"] {
            #expect(throws: (any Error).self) {
                try InviteLink.invite(from: URL(string: bad)!)
            }
        }
    }

    @Test("Expiry is reported against the clock")
    func reportsExpiry() {
        let invite = sample()
        #expect(!invite.hasExpired(now: invite.expiresAt.addingTimeInterval(-1)))
        #expect(invite.hasExpired(now: invite.expiresAt.addingTimeInterval(1)))
    }

    @Test("base64url avoids the characters a URL needs for itself")
    func base64urlIsUrlSafe() {
        // Bytes chosen to force + and / in standard base64.
        let data = Data([0xFB, 0xEF, 0xFE, 0xFF, 0x3F, 0x3E])
        let encoded = InviteLink.base64url(data)
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(InviteLink.data(fromBase64url: encoded) == data)
    }

    @Test("Padding is restored for every length")
    func restoresPadding() {
        for length in 1...16 {
            let data = Data((0..<length).map { UInt8($0) })
            let encoded = InviteLink.base64url(data)
            #expect(InviteLink.data(fromBase64url: encoded) == data, "length \(length)")
        }
    }

    @Test("A name with spaces and punctuation survives")
    func handlesAwkwardNames() throws {
        var invite = sample(username: "sam.o'neill")
        invite.displayName = "Sam O'Neill — Dad's iPad"
        invite.serverName = "Books & Things"
        let decoded = try InviteLink.invite(from: try InviteLink.url(for: invite))
        #expect(decoded == invite)
    }
}

@Suite("Temporary passwords")
struct TemporaryPasswordTests {
    @Test("Long enough to be worth generating")
    func hasAMinimumLength() {
        #expect(TemporaryPassword.make().count == 24)
        #expect(TemporaryPassword.make(length: 4).count == 12)
    }

    @Test("No characters that are misread when copied by hand")
    func avoidsAmbiguousCharacters() {
        let generated = (0..<50).map { _ in TemporaryPassword.make() }.joined()
        for ambiguous in ["l", "1", "i", "o", "0", "O", "I"] {
            #expect(!generated.contains(ambiguous), "contained \(ambiguous)")
        }
    }

    @Test("Two passwords are not the same")
    func isNotPredictable() {
        let generated = Set((0..<100).map { _ in TemporaryPassword.make() })
        #expect(generated.count == 100)
    }
}
