import Foundation
import Testing
@testable import SyncEngine

private func position(
    seconds: TimeInterval? = nil,
    ebookProgress: Double? = nil,
    ebookLocation: String? = nil,
    finished: Bool = false,
    at updatedAt: Date,
    device: String = "iPhone"
) -> ProgressPosition {
    ProgressPosition(
        itemID: "li-1",
        currentTime: seconds,
        duration: 36_000,
        ebookLocation: ebookLocation,
        ebookProgress: ebookProgress,
        isFinished: finished,
        updatedAt: updatedAt,
        deviceID: device.lowercased(),
        deviceLabel: device
    )
}

@Suite("Progress conflict resolution")
struct ProgressConflictResolverTests {
    private let resolver = ProgressConflictResolver()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The same place needs no decision")
    func identicalPositions() {
        let local = position(seconds: 1200, at: now)
        let remote = position(seconds: 1200, at: now.addingTimeInterval(30), device: "iPad")
        #expect(resolver.resolve(local: local, remote: remote) == .noChange)
    }

    @Test("A second of drift is sync lag, not a conflict")
    func epsilon() {
        let local = position(seconds: 1200, at: now)
        let remote = position(seconds: 1200.4, at: now.addingTimeInterval(10), device: "iPad")
        #expect(resolver.resolve(local: local, remote: remote) == .noChange)
    }

    @Test("A newer remote within the threshold is taken silently")
    func smallForwardJump() {
        let local = position(seconds: 1200, at: now)
        let remote = position(seconds: 1260, at: now.addingTimeInterval(60), device: "iPad")
        #expect(resolver.resolve(local: local, remote: remote) == .takeRemote)
    }

    @Test("An older remote never wins, however far it has moved")
    func staleRemoteIgnored() {
        let local = position(seconds: 1200, at: now)
        let remote = position(seconds: 9000, at: now.addingTimeInterval(-60), device: "iPad")
        #expect(resolver.resolve(local: local, remote: remote) == .keepLocal)
    }

    @Test("A large forward jump asks rather than moving the user")
    func largeForwardJumpAsks() throws {
        let local = position(seconds: 12_005, at: now)                                  // 3:20:05
        let remote = position(seconds: 13_330, at: now.addingTimeInterval(120), device: "iPad") // 3:42:10
        let outcome = resolver.resolve(local: local, remote: remote)

        guard case .ask(let askLocal, let askRemote) = outcome else {
            Issue.record("Expected a prompt, got \(outcome)")
            return
        }
        #expect(askLocal.currentTime == 12_005)
        #expect(askRemote.currentTime == 13_330)
        #expect(askRemote.deviceLabel == "iPad")
    }

    @Test("A large backward jump asks too — losing your place is losing your place")
    func largeBackwardJumpAsks() {
        let local = position(seconds: 13_330, at: now)
        let remote = position(seconds: 12_005, at: now.addingTimeInterval(120), device: "iPad")
        guard case .ask = resolver.resolve(local: local, remote: remote) else {
            Issue.record("Expected a prompt")
            return
        }
    }

    @Test("Exactly at the threshold is not yet large")
    func thresholdBoundary() {
        let local = position(seconds: 1000, at: now)
        let atThreshold = position(seconds: 1120, at: now.addingTimeInterval(10), device: "iPad")
        #expect(resolver.resolve(local: local, remote: atThreshold) == .takeRemote)

        let justOver = position(seconds: 1120.5, at: now.addingTimeInterval(10), device: "iPad")
        guard case .ask = resolver.resolve(local: local, remote: justOver) else {
            Issue.record("Expected a prompt just past the threshold")
            return
        }
    }

    @Test("Ebooks use a percentage threshold")
    func ebookThreshold() {
        let local = position(ebookProgress: 0.50, at: now)

        let small = position(ebookProgress: 0.515, at: now.addingTimeInterval(60), device: "iPad")
        #expect(resolver.resolve(local: local, remote: small) == .takeRemote)

        let large = position(ebookProgress: 0.60, at: now.addingTimeInterval(60), device: "iPad")
        guard case .ask = resolver.resolve(local: local, remote: large) else {
            Issue.record("Expected a prompt for a 10% jump")
            return
        }
    }

    @Test("Two locators with no percentage to compare ask rather than guess")
    func unmeasurableEbookJump() {
        let local = position(ebookLocation: "{\"href\":\"ch3.xhtml\"}", at: now)
        let remote = position(ebookLocation: "{\"href\":\"ch9.xhtml\"}", at: now.addingTimeInterval(60), device: "iPad")
        guard case .ask = resolver.resolve(local: local, remote: remote) else {
            Issue.record("Expected a prompt")
            return
        }
    }

    @Test("Nothing local means nothing to lose")
    func missingSides() {
        let remote = position(seconds: 900, at: now, device: "iPad")
        #expect(resolver.resolve(local: nil, remote: remote) == .takeRemote)
        #expect(resolver.resolve(local: remote, remote: nil) == .keepLocal)
        #expect(resolver.resolve(local: nil, remote: nil) == .noChange)
    }

    @Test("An empty remote never overwrites real local progress")
    func emptyRemote() {
        let local = position(seconds: 1200, at: now)
        let empty = ProgressPosition(itemID: "li-1", updatedAt: now.addingTimeInterval(600), deviceID: "x", deviceLabel: "iPad")
        #expect(resolver.resolve(local: local, remote: empty) == .keepLocal)
    }

    @Test("A finished flag is adopted at the same position without a prompt")
    func finishedFlag() {
        let local = position(seconds: 1200, at: now)
        let remote = position(seconds: 1200, finished: true, at: now.addingTimeInterval(60), device: "iPad")
        #expect(resolver.resolve(local: local, remote: remote) == .takeRemote)
    }
}

@Suite("Progress position")
struct ProgressPositionTests {
    @Test("Podcast progress is keyed locally by item and episode")
    func localKey() {
        let book = ProgressPosition(itemID: "li-1", deviceID: "d", deviceLabel: "iPhone")
        #expect(book.localKey == "li-1")

        let episode = ProgressPosition(itemID: "li-1", episodeID: "ep-7", deviceID: "d", deviceLabel: "iPhone")
        #expect(episode.localKey == "li-1/ep-7")
    }

    @Test("Audio progress is clamped to 0...1")
    func audioProgress() {
        let half = ProgressPosition(itemID: "x", currentTime: 50, duration: 100, deviceID: "d", deviceLabel: "iPhone")
        #expect(half.audioProgress == 0.5)

        let overrun = ProgressPosition(itemID: "x", currentTime: 150, duration: 100, deviceID: "d", deviceLabel: "iPhone")
        #expect(overrun.audioProgress == 1.0)

        let unknown = ProgressPosition(itemID: "x", currentTime: 50, duration: 0, deviceID: "d", deviceLabel: "iPhone")
        #expect(unknown.audioProgress == nil)
    }
}
