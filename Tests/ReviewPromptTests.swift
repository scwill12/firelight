import Foundation
import Testing
@testable import Persistence

@Suite("Asking for a rating")
struct ReviewPromptTests {
    @Test("The first two opens pass in silence")
    func quietAtFirst() {
        #expect(ReviewPrompt.shouldAsk(opens: 1, lastAsk: nil, version: "1.0") == false)
        #expect(ReviewPrompt.shouldAsk(opens: 2, lastAsk: nil, version: "1.0") == false)
    }

    @Test("The third open asks")
    func asksOnTheThird() {
        #expect(ReviewPrompt.shouldAsk(opens: 3, lastAsk: nil, version: "1.0"))
    }

    @Test("Having asked, this version never asks again")
    func neverTwicePerVersion() {
        let asked = ReviewPrompt.Ask(version: "1.0", opens: 3)
        for opens in 4...40 {
            #expect(ReviewPrompt.shouldAsk(opens: opens, lastAsk: asked, version: "1.0") == false)
        }
    }

    @Test("A new version asks again, but not immediately")
    func aNewVersionWaitsItsTurn() {
        let asked = ReviewPrompt.Ask(version: "1.0", opens: 3)
        // Updating is not itself a reason to be asked again.
        #expect(ReviewPrompt.shouldAsk(opens: 4, lastAsk: asked, version: "1.1") == false)
        #expect(ReviewPrompt.shouldAsk(opens: 5, lastAsk: asked, version: "1.1") == false)
        #expect(ReviewPrompt.shouldAsk(opens: 6, lastAsk: asked, version: "1.1"))
    }

    @Test("Someone who installs an update before ever being asked still is")
    func upgradeDoesNotLoseTheFirstAsk() {
        #expect(ReviewPrompt.shouldAsk(opens: 3, lastAsk: nil, version: "1.1"))
    }
}

@Suite("The open counter")
struct ReviewPromptStoreTests {
    private func store() -> (ReviewPromptStore, UserDefaults, String) {
        let suite = "firelight.tests.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return (ReviewPromptStore(defaults: defaults), defaults, suite)
    }

    @Test("Opens accumulate and the third one asks")
    func countsOpens() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.recordOpen(version: "1.0") == false)
        #expect(store.recordOpen(version: "1.0") == false)
        #expect(store.recordOpen(version: "1.0"))
        #expect(store.opens == 3)
        #expect(store.lastAsk == ReviewPrompt.Ask(version: "1.0", opens: 3))
    }

    @Test("A fourth open does not ask again")
    func doesNotRepeat() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        for _ in 1...3 { _ = store.recordOpen(version: "1.0") }
        #expect(store.recordOpen(version: "1.0") == false)
        #expect(store.recordOpen(version: "1.0") == false)
    }

    @Test("The ask is recorded even though StoreKit may show nothing")
    func recordsTheAskNotThePrompt() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        for _ in 1...3 { _ = store.recordOpen(version: "1.0") }
        // A second store over the same defaults is a fresh launch.
        let next = ReviewPromptStore(defaults: defaults)
        #expect(next.lastAsk?.version == "1.0")
        #expect(next.recordOpen(version: "1.0") == false)
    }

    @Test("A store with nothing written has never asked")
    func emptyStore() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.opens == 0)
        #expect(store.lastAsk == nil)
    }
}
