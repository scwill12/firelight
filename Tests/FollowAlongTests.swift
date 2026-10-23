import Foundation
import Testing
@testable import Persistence
@testable import ReaderKit

@Suite("Follow along in the printed text")
struct FollowAlongTests {
    private let kindle = ReadingEdition(unit: .location, lastPosition: 9_112)
    private let paperback = ReadingEdition(unit: .page, lastPosition: 480)

    @Test("The start of the book is the first location, not the zeroth")
    func startsAtOne() throws {
        let position = try #require(FollowAlong.position(progress: 0, edition: kindle))
        #expect(position.value == 1)
        #expect(position.unit == .location)
        #expect(position.total == 9_112)
    }

    @Test("The end of the book is the last location")
    func endsAtTotal() throws {
        let position = try #require(FollowAlong.position(progress: 1, edition: kindle))
        #expect(position.value == 9_112)
    }

    @Test("Halfway through the audio is halfway through the text")
    func mapsLinearly() throws {
        let position = try #require(FollowAlong.position(progress: 0.5, edition: paperback))
        // 1 + round(0.5 * 479) = 1 + 240 = 241.
        #expect(position.value == 241)
    }

    @Test("Progress outside the book is clamped, not extrapolated")
    func clampsOutOfRange() throws {
        let before = try #require(FollowAlong.position(progress: -0.5, edition: paperback))
        let after = try #require(FollowAlong.position(progress: 1.8, edition: paperback))
        #expect(before.value == 1)
        #expect(after.value == 480)
    }

    @Test("An edition with no length says nothing rather than zero")
    func refusesToGuess() {
        #expect(FollowAlong.position(progress: 0.5, edition: ReadingEdition(unit: .page, lastPosition: 0)) == nil)
        #expect(FollowAlong.position(progress: 0.5, edition: ReadingEdition(unit: .page, lastPosition: -3)) == nil)
    }

    @Test("A non-finite progress says nothing")
    func refusesNonFiniteProgress() {
        #expect(FollowAlong.position(progress: .nan, edition: paperback) == nil)
        #expect(FollowAlong.position(progress: .infinity, edition: paperback) == nil)
    }

    @Test("A one-page edition is always on its only page")
    func singlePageEdition() throws {
        let edition = ReadingEdition(unit: .page, lastPosition: 1)
        let start = try #require(FollowAlong.position(progress: 0, edition: edition))
        let end = try #require(FollowAlong.position(progress: 1, edition: edition))
        #expect(start.value == 1)
        #expect(end.value == 1)
    }

    @Test("A page read off the device maps back to a place in the audio")
    func mapsBackToAudio() throws {
        let progress = try #require(FollowAlong.progress(atPosition: 241, edition: paperback))
        #expect(abs(progress - 0.5) < 0.005)
        #expect(FollowAlong.progress(atPosition: 1, edition: paperback) == 0)
        #expect(FollowAlong.progress(atPosition: 480, edition: paperback) == 1)
    }

    @Test("Mapping back clamps a position the edition does not contain")
    func mapsBackClamped() {
        #expect(FollowAlong.progress(atPosition: 0, edition: paperback) == 0)
        #expect(FollowAlong.progress(atPosition: 10_000, edition: paperback) == 1)
        #expect(FollowAlong.progress(atPosition: 5, edition: ReadingEdition(unit: .page, lastPosition: 1)) == nil)
    }

    @Test("A round trip through both maps lands back where it started")
    func roundTrips() throws {
        for page in [1, 50, 241, 479, 480] {
            let progress = try #require(FollowAlong.progress(atPosition: page, edition: paperback))
            let back = try #require(FollowAlong.position(progress: progress, edition: paperback))
            #expect(back.value == page)
        }
    }

    @Test("Only Kindle counts in locations, and only Kindle offers a choice")
    func deviceUnits() {
        #expect(ReadingDevice.kindle.defaultUnit == .location)
        #expect(ReadingDevice.kindle.offersBothUnits)
        for device in [ReadingDevice.kobo, .nook, .appleBooks, .print] {
            #expect(device.defaultUnit == .page)
            #expect(!device.offersBothUnits)
        }
    }
}

@Suite("Reading edition store")
struct ReadingEditionStoreTests {
    private func store() -> (ReadingEditionStore, UserDefaults, String) {
        let suite = "firelight.tests.editions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return (ReadingEditionStore(defaults: defaults), defaults, suite)
    }

    @Test("An edition survives a round trip")
    func roundTrips() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.edition(forItemID: "book-1") == nil)
        store.save(.init(itemID: "book-1", deviceRaw: "kindle", unitRaw: "location", lastPosition: 9_112))

        let stored = try #require(store.edition(forItemID: "book-1"))
        #expect(stored.lastPosition == 9_112)
        #expect(stored.unitRaw == "location")
        #expect(stored.deviceRaw == "kindle")
    }

    @Test("Books are kept apart")
    func booksAreIndependent() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(.init(itemID: "book-1", deviceRaw: "kindle", unitRaw: "location", lastPosition: 9_112))
        store.save(.init(itemID: "book-2", deviceRaw: "kobo", unitRaw: "page", lastPosition: 412))

        #expect(try #require(store.edition(forItemID: "book-1")).lastPosition == 9_112)
        #expect(try #require(store.edition(forItemID: "book-2")).lastPosition == 412)
    }

    @Test("Saving again replaces rather than duplicates")
    func savingReplaces() throws {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(.init(itemID: "book-1", deviceRaw: "kindle", unitRaw: "location", lastPosition: 9_112))
        store.save(.init(itemID: "book-1", deviceRaw: "kindle", unitRaw: "page", lastPosition: 480))

        let stored = try #require(store.edition(forItemID: "book-1"))
        #expect(stored.lastPosition == 480)
        #expect(stored.unitRaw == "page")
    }

    @Test("Forgetting one book leaves the others alone")
    func removingIsTargeted() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save(.init(itemID: "book-1", deviceRaw: "kindle", unitRaw: "location", lastPosition: 9_112))
        store.save(.init(itemID: "book-2", deviceRaw: "kobo", unitRaw: "page", lastPosition: 412))
        store.remove(itemID: "book-1")

        #expect(store.edition(forItemID: "book-1") == nil)
        #expect(store.edition(forItemID: "book-2") != nil)
    }
}

@Suite("Calibrating against a foreword")
struct CalibrationTests {
    /// A book whose audio opens with a foreword filling the first 10%, after
    /// which the printed text runs from location 1 to 9,000.
    private let withForeword = ReadingEdition(
        unit: .location,
        firstPosition: 1,
        lastPosition: 9_000,
        startProgress: 0.1,
        endProgress: 1
    )

    @Test("The page does not move while the foreword plays")
    func forewordHoldsTheFirstPosition() throws {
        for progress in [0.0, 0.03, 0.09, 0.1] {
            let position = try #require(
                FollowAlong.position(progress: progress, edition: withForeword)
            )
            #expect(position.value == 1)
        }
    }

    @Test("After the text starts it runs evenly to the end")
    func runsEvenlyAfterTheStart() throws {
        // Halfway between the 10% mark and the end.
        let middle = try #require(
            FollowAlong.position(progress: 0.55, edition: withForeword)
        )
        #expect(middle.value == 4_501)
        let end = try #require(FollowAlong.position(progress: 1, edition: withForeword))
        #expect(end.value == 9_000)
    }

    @Test("Without calibration the same book reads ahead of itself")
    func uncalibratedRunsAhead() throws {
        let plain = ReadingEdition(unit: .location, lastPosition: 9_000)
        let wrong = try #require(FollowAlong.position(progress: 0.1, edition: plain))
        // 10% in, it already claims 900 locations of a book that has not begun.
        #expect(wrong.value == 901)
    }

    @Test("Back matter holds the last position instead of overrunning")
    func backMatterHoldsTheEnd() throws {
        // The last 8% is an excerpt of the next book.
        let edition = ReadingEdition(
            unit: .page,
            lastPosition: 400,
            startProgress: 0,
            endProgress: 0.92
        )
        for progress in [0.92, 0.95, 1.0] {
            let position = try #require(FollowAlong.position(progress: progress, edition: edition))
            #expect(position.value == 400)
        }
    }

    @Test("An edition can start numbering above one")
    func numberingCanStartAboveOne() throws {
        // Chapter one opens on page 12 because the foreword is numbered too.
        let edition = ReadingEdition(unit: .page, firstPosition: 12, lastPosition: 492)
        let start = try #require(FollowAlong.position(progress: 0, edition: edition))
        let end = try #require(FollowAlong.position(progress: 1, edition: edition))
        #expect(start.value == 12)
        #expect(end.value == 492)
        #expect(start.total == 492)
    }

    @Test("Calibration points that cross over are ignored, not obeyed")
    func crossedCalibrationIsIgnored() throws {
        let crossed = ReadingEdition(
            unit: .page,
            lastPosition: 400,
            startProgress: 0.9,
            endProgress: 0.2
        )
        let middle = try #require(FollowAlong.position(progress: 0.5, edition: crossed))
        // Falls back to the plain map: 1 + round(0.5 * 399).
        #expect(middle.value == 201)
    }

    @Test("An edition that runs backwards is refused")
    func backwardsEditionIsRefused() {
        let backwards = ReadingEdition(unit: .page, firstPosition: 400, lastPosition: 10)
        #expect(FollowAlong.position(progress: 0.5, edition: backwards) == nil)
    }

    @Test("A calibrated book still round-trips back to the audio")
    func calibratedRoundTrip() throws {
        for position in [1, 2_000, 4_501, 9_000] {
            let progress = try #require(
                FollowAlong.progress(atPosition: position, edition: withForeword)
            )
            #expect(progress >= 0.1)
            let back = try #require(
                FollowAlong.position(progress: progress, edition: withForeword)
            )
            #expect(abs(back.value - position) <= 1)
        }
    }

    @Test("Calibration is only reported when it would change anything")
    func reportsWhetherItIsCalibrated() {
        #expect(!ReadingEdition(unit: .page, lastPosition: 400).isCalibrated)
        #expect(withForeword.isCalibrated)
        #expect(ReadingEdition(unit: .page, lastPosition: 400, endProgress: 0.9).isCalibrated)
    }
}

@Suite("Editions written before calibration existed")
struct ReadingEditionMigrationTests {
    @Test("An entry with only a total still decodes")
    func oldEntryDecodes() throws {
        let suite = "firelight.tests.legacy.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Exactly what the first version of the store wrote.
        let legacy = """
        {"book-1":{"deviceRaw":"kindle","unitRaw":"location","total":9112}}
        """
        defaults.set(Data(legacy.utf8), forKey: "firelight.followAlong.editions")

        let stored = try #require(
            ReadingEditionStore(defaults: defaults).edition(forItemID: "book-1")
        )
        #expect(stored.lastPosition == 9_112)
        #expect(stored.firstPosition == 1)
        #expect(stored.startProgress == 0)
        #expect(stored.endProgress == 1)
    }
}
