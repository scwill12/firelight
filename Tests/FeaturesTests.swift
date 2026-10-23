import UIKit
import MediaPlayer
import Testing
@testable import ABSKit
@testable import Features

@Suite("Foundation self-checks", .serialized)
struct FoundationCheckerTests {
    private var checker: FoundationChecker {
        FoundationChecker(
            keychain: KeychainStore(service: "com.colewilliams.firelight.tests.checks", accessGroup: nil),
            storeOpened: true
        )
    }

    @Test("Reports on all three foundations")
    func runsEveryCheck() {
        let results = checker.run()
        #expect(results.map(\.id) == ["appGroup", "keychain", "store"])
    }

    @Test("The Keychain check actually round-trips a value")
    func keychainCheckPasses() {
        let check = checker.keychainCheck()
        #expect(check.outcome.didPass, "Keychain check failed: \(check.outcome.detail)")
    }

    @Test("A store that didn't open is reported, not hidden")
    func storeFailureSurfaces() {
        let failing = FoundationChecker(
            keychain: KeychainStore(service: "x", accessGroup: nil),
            storeOpened: false,
            storeFailureDetail: "The App Group isn't available to this build."
        )
        let check = failing.storeCheck()
        #expect(!check.outcome.didPass)
        #expect(check.outcome.detail == "The App Group isn't available to this build.")
    }
}

@Suite("Publication year")
struct PublicationYearTests {
    @Test("A full ISO timestamp is reduced to its year")
    func isoTimestampBecomesYear() {
        #expect(Format.publicationYear("2024-07-26T00:00:00") == "2024")
        #expect(Format.publicationYear("2024-07-26") == "2024")
    }

    @Test("A plain year is left alone")
    func plainYearSurvives() {
        #expect(Format.publicationYear("2024") == "2024")
        #expect(Format.publicationYear(" 1998 ") == "1998")
    }

    @Test("Anything that isn't a date is passed through rather than mangled")
    func nonDatePassesThrough() {
        #expect(Format.publicationYear("MCMXCVIII") == "MCMXCVIII")
        #expect(Format.publicationYear("") == "")
    }
}

@Suite("Now Playing artwork")
struct NowPlayingArtworkTests {
    private func solidImage() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// The regression that killed the app on every play.
    ///
    /// `MPMediaItemArtwork` asks for its image on MediaPlayer's own queue. When
    /// the request handler was built inside a `@MainActor` method it inherited
    /// that isolation, and the runtime check Swift inserts trapped off-main.
    /// Asking for the image from a background queue is what reproduces it.
    @Test("The request handler can be called off the main actor")
    func handlerIsNotActorIsolated() async {
        let artwork = AppEnvironment.artwork(for: solidImage())

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = artwork.image(at: CGSize(width: 16, height: 16))
                continuation.resume()
            }
        }
    }

    @Test("The artwork reports the bounds it was built with")
    func artworkKeepsItsBounds() {
        let artwork = AppEnvironment.artwork(for: solidImage())
        #expect(artwork.bounds.size == CGSize(width: 32, height: 32))
    }
}
