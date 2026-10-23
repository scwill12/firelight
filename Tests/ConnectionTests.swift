import Foundation
import Testing
@testable import ABSKit

/// Records what the resolver probed. An actor because the prober is
/// `@Sendable` and Swift 6 will not let a closure mutate a captured var.
private actor ProbeLog {
    private(set) var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
    var count: Int { urls.count }
}

@Suite("Server address resolution")
struct ServerAddressResolverTests {
    private let local = URL(string: "http://books.lan:13378")!
    private let remote = URL(string: "https://books.example.com")!

    private func descriptor(withLocal: Bool = true) -> ServerDescriptor {
        ServerDescriptor(
            displayName: "Home",
            localURL: withLocal ? local : nil,
            remoteURL: remote
        )
    }

    @Test("Prefers the local address whenever it answers")
    func prefersLocal() async {
        let resolver = ServerAddressResolver { _ in true }
        let resolved = await resolver.resolve(descriptor())
        #expect(resolved?.kind == .local)
        #expect(resolved?.url == local)
    }

    @Test("Falls back to the remote address when the local one is silent")
    func fallsBackToRemote() async {
        let localURL = local
        let resolver = ServerAddressResolver { url in url != localURL }
        let resolved = await resolver.resolve(descriptor())
        #expect(resolved?.kind == .remote)
        #expect(resolved?.url == remote)
    }

    @Test("Returns nothing when neither answers, so the app can go offline cleanly")
    func neitherReachable() async {
        let resolver = ServerAddressResolver { _ in false }
        #expect(await resolver.resolve(descriptor()) == nil)
    }

    @Test("A server with only a remote address skips the race")
    func remoteOnly() async {
        let log = ProbeLog()
        let resolver = ServerAddressResolver { url in
            await log.record(url)
            return true
        }
        let resolved = await resolver.resolve(descriptor(withLocal: false))
        #expect(resolved?.kind == .remote)
        #expect(await log.urls == [remote])
    }

    @Test("Both addresses are probed at once, so being away costs nothing")
    func probesConcurrently() async {
        let localURL = local
        let resolver = ServerAddressResolver { url in
            // The local probe is the slow one when you are away from home.
            if url == localURL {
                try? await Task.sleep(for: .milliseconds(120))
                return false
            }
            return true
        }
        let started = ContinuousClock.now
        let resolved = await resolver.resolve(descriptor())
        let elapsed = ContinuousClock.now - started

        #expect(resolved?.kind == .remote)
        // Sequential probing would have cost the local timeout plus the remote
        // round trip; concurrent probing costs only the slower of the two.
        #expect(elapsed < .milliseconds(400))
    }

    @Test("A local address identical to the remote one isn't raced twice")
    func identicalAddresses() async {
        let log = ProbeLog()
        let resolver = ServerAddressResolver { url in
            await log.record(url)
            return true
        }
        let descriptor = ServerDescriptor(displayName: "Same", localURL: remote, remoteURL: remote)
        let resolved = await resolver.resolve(descriptor)
        #expect(resolved?.kind == .remote)
        #expect(await log.count == 1)
    }
}

@Suite("Certificate trust")
struct CertificateTrustTests {
    private let fingerprint = CertificateFingerprint(sha256: Data((0..<32).map { UInt8($0) }))

    @Test("A fingerprint reads as grouped hex a person can compare")
    func fingerprintFormatting() {
        #expect(fingerprint.description.hasPrefix("00:01:02:03"))
        #expect(fingerprint.description.split(separator: ":").count == 32)
    }

    @Test("Nothing is trusted until the user trusts it")
    func defaultsToUntrusted() async {
        let coordinator = CertificateTrustCoordinator()
        #expect(await coordinator.trustedFingerprint(forHost: "books.lan") == nil)
    }

    @Test("Trusting the rejected certificate is what the user is actually doing")
    func trustRejected() async {
        let coordinator = CertificateTrustCoordinator()
        await coordinator.recordRejected(fingerprint, forHost: "Books.LAN")

        // Host matching is case-insensitive, as hostnames are.
        #expect(await coordinator.rejectedFingerprint(forHost: "books.lan") == fingerprint)
        #expect(await coordinator.trustRejected(forHost: "books.lan"))
        #expect(await coordinator.trustedFingerprint(forHost: "BOOKS.LAN") == fingerprint)
    }

    @Test("Trust cannot be granted for a host that never offered a certificate")
    func cannotTrustUnseenHost() async {
        let coordinator = CertificateTrustCoordinator()
        #expect(await coordinator.trustRejected(forHost: "never-seen.example") == false)
    }

    @Test("Trust is per host, and revocable")
    func revoking() async {
        let coordinator = CertificateTrustCoordinator()
        await coordinator.trust(fingerprint, forHost: "books.lan")
        #expect(await coordinator.trustedFingerprint(forHost: "other.lan") == nil)

        await coordinator.revokeTrust(forHost: "books.lan")
        #expect(await coordinator.trustedFingerprint(forHost: "books.lan") == nil)
    }
}

@Suite("Address field prefill")
struct ServerURLParserBlankTests {
    @Test("The prefilled scheme does not count as an address")
    func schemeAloneIsBlank() {
        #expect(ServerURLParser.isBlank(ServerURLParser.defaultScheme))
        #expect(ServerURLParser.isBlank(""))
        #expect(ServerURLParser.isBlank("   "))
        #expect(ServerURLParser.isBlank("https:/"))
        #expect(ServerURLParser.isBlank("http"))
        #expect(ServerURLParser.isBlank("HTTPS://"))
    }

    @Test("Anything with a host in it counts as an address")
    func hostIsNotBlank() {
        #expect(!ServerURLParser.isBlank("https://books.example.com"))
        #expect(!ServerURLParser.isBlank("books.example.com"))
        // A single-label LAN name is not a prefix of either scheme, so it
        // reads as an address the moment it is typed.
        #expect(!ServerURLParser.isBlank("nas"))
        #expect(!ServerURLParser.isBlank("htpc"))
    }

    @Test("The scheme Firelight prefills is the one it would have added anyway")
    func prefillMatchesTheParser() throws {
        let typed = try #require(ServerURLParser.parse("books.example.com"))
        let prefilled = try #require(
            ServerURLParser.parse(ServerURLParser.defaultScheme + "books.example.com")
        )
        #expect(typed == prefilled)
    }
}
