import Foundation
import Testing
@testable import ABSKit

@Suite("Invitation codes")
struct InviteCodeTests {
    private func sample(
        expiresIn: TimeInterval = 7 * 24 * 60 * 60,
        username: String = "sam"
    ) -> Invite {
        Invite(
            serverURL: URL(string: "https://books.example.com:13378/abs")!,
            username: username,
            temporaryPassword: "abcdefghjkmn",
            expiresAt: Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(expiresIn)
        )
    }

    @Test("An invitation survives the round trip through a code")
    func roundTrips() throws {
        let invite = sample()
        let code = try InviteCode.make(from: invite)
        #expect(try InviteCode.invite(from: code) == invite)
    }

    @Test("The server's own sub-path is preserved")
    func keepsTheSubPath() throws {
        // Audiobookshelf can live under a RouterBasePath; dropping it would
        // point the invited person at a server that is not there.
        let decoded = try InviteCode.invite(from: try InviteCode.make(from: sample()))
        #expect(decoded.serverURL.absoluteString == "https://books.example.com:13378/abs")
    }

    @Test("The password is not legible in the code")
    func passwordIsNotPlainText() throws {
        let code = try InviteCode.make(from: sample())
        // Encoding, not encryption — but a message preview should not render
        // somebody's password as readable text beside their name.
        #expect(!code.contains("abcdefghjkmn"))
        #expect(!code.lowercased().contains("example.com"))
    }

    @Test("It is marked as an invitation, so a stray paste is recognisable")
    func carriesItsPrefix() throws {
        #expect(try InviteCode.make(from: sample()).hasPrefix("FL1"))
    }

    @Test("Short enough to read as a code rather than a paragraph")
    func staysShort() throws {
        let code = try InviteCode.make(from: sample())
        // Carrying the server's name and the person's name here instead of
        // reading them from the server after login cost about forty.
        #expect(code.count < 140, "code was \(code.count) characters")
    }

    @Test("Whitespace a message added is ignored")
    func toleratesWrapping() throws {
        let invite = sample()
        let code = try InviteCode.make(from: invite)
        let mangled = "  " + code.prefix(20) + "\n" + code.dropFirst(20) + " \n"
        #expect(try InviteCode.invite(from: String(mangled)) == invite)
    }

    @Test("Something that is not an invitation is refused, not misread")
    func refusesOtherText() {
        for other in ["", "hello", "https://example.com", "FL2abc", "fl1abc"] {
            #expect(throws: (any Error).self) {
                try InviteCode.invite(from: other)
            }
        }
    }

    @Test("A damaged code is refused rather than half-read")
    func refusesDamagedCodes() {
        for bad in ["FL1", "FL1!!!!", "FL1YWJj"] {
            #expect(throws: (any Error).self) {
                try InviteCode.invite(from: bad)
            }
        }
    }

    @Test("A truncated code is refused rather than decoding to nonsense")
    func refusesTruncation() throws {
        let code = try InviteCode.make(from: sample())
        #expect(throws: (any Error).self) {
            try InviteCode.invite(from: String(code.dropLast(10)))
        }
    }

    @Test("Expiry is reported against the clock")
    func reportsExpiry() {
        let invite = sample()
        #expect(!invite.hasExpired(now: invite.expiresAt.addingTimeInterval(-1)))
        #expect(invite.hasExpired(now: invite.expiresAt.addingTimeInterval(1)))
    }

    @Test("base64url avoids characters a messaging app would mangle")
    func base64urlIsSafe() {
        let data = Data([0xFB, 0xEF, 0xFE, 0xFF, 0x3F, 0x3E])
        let encoded = InviteCode.base64url(data)
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
        #expect(InviteCode.data(fromBase64url: encoded) == data)
    }

    @Test("Padding is restored for every length")
    func restoresPadding() {
        for length in 1...16 {
            let data = Data((0..<length).map { UInt8($0) })
            #expect(InviteCode.data(fromBase64url: InviteCode.base64url(data)) == data,
                    "length \(length)")
        }
    }

    @Test("A username with punctuation survives")
    func handlesAwkwardNames() throws {
        let invite = sample(username: "sam.o'neill")
        #expect(try InviteCode.invite(from: try InviteCode.make(from: invite)) == invite)
    }

    @Test("A code naming no server or no user is refused")
    func refusesIncompletePayloads() {
        for payload in [#"{"u":"","n":"sam","p":"x","e":1}"#,
                        #"{"u":"https://a.example.com","n":"","p":"x","e":1}"#,
                        #"{"u":"https://a.example.com","n":"sam","p":"","e":1}"#] {
            let code = InviteCode.prefix + InviteCode.base64url(Data(payload.utf8))
            #expect(throws: InviteError.self) { try InviteCode.invite(from: code) }
        }
    }
}

@Suite("Temporary passwords")
struct TemporaryPasswordTests {
    @Test("Long enough to be worth generating")
    func hasAMinimumLength() {
        #expect(TemporaryPassword.make().count == 16)
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
