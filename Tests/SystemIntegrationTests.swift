import Foundation
import Testing
@testable import Features
@testable import Persistence

@Suite("Now playing snapshot")
struct NowPlayingSnapshotTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(position: TimeInterval, playing: Bool) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            itemID: "li-1", title: "A Book", author: "An Author",
            chapterTitle: "One", position: position, duration: 3600,
            isPlaying: playing, updatedAt: start
        )
    }

    @Test("A playing snapshot advances itself, so a widget stays honest")
    func projectsWhilePlaying() {
        // A widget redraws on the system's schedule, not the app's. Without
        // this the bar would freeze at whatever the app last wrote.
        let projected = snapshot(position: 100, playing: true)
            .projected(to: start.addingTimeInterval(60))
        #expect(projected.position == 160)
    }

    @Test("A paused snapshot does not drift")
    func pausedDoesNotProject() {
        let projected = snapshot(position: 100, playing: false)
            .projected(to: start.addingTimeInterval(600))
        #expect(projected.position == 100)
    }

    @Test("Projection stops at the end of the book")
    func clampsToDuration() {
        let projected = snapshot(position: 3500, playing: true)
            .projected(to: start.addingTimeInterval(9999))
        #expect(projected.position == 3600)
        #expect(projected.fraction == 1)
    }

    @Test("A clock that went backwards does not rewind the position")
    func ignoresBackwardsClock() {
        let projected = snapshot(position: 100, playing: true)
            .projected(to: start.addingTimeInterval(-500))
        #expect(projected.position == 100)
    }

    @Test("Fraction and time left agree with each other")
    func derivedValues() {
        let value = snapshot(position: 900, playing: true)
        #expect(value.fraction == 0.25)
        #expect(value.timeRemaining == 2700)
    }

    @Test("A zero-duration item reports no progress rather than dividing by zero")
    func zeroDuration() {
        let value = NowPlayingSnapshot(
            itemID: "x", title: "T", position: 10, duration: 0, isPlaying: true
        )
        #expect(value.fraction == 0)
    }

    @Test("Survives the round trip through the shared container")
    func codable() throws {
        let original = snapshot(position: 123, playing: true)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(NowPlayingSnapshot.self, from: data) == original)
    }
}

@Suite("Listening streak")
struct ListeningStreakTests {
    private let streak = ListeningStreak(calendar: {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }())

    /// Midday, so a day's arithmetic never lands on a boundary by accident.
    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysAgo(_ count: Int) -> Date {
        today.addingTimeInterval(TimeInterval(-count) * 86_400)
    }

    @Test("Consecutive days count")
    func consecutive() {
        let dates = (0...4).map(daysAgo)
        #expect(streak.currentStreak(from: dates, now: today) == 5)
    }

    @Test("Yesterday still counts, so the streak survives the morning")
    func yesterdayCounts() {
        // Someone who listens every evening should not lose their streak at
        // midnight before they have had a chance to listen.
        let dates = [daysAgo(1), daysAgo(2), daysAgo(3)]
        #expect(streak.currentStreak(from: dates, now: today) == 3)
    }

    @Test("A gap ends the streak")
    func gapEndsIt() {
        let dates = [daysAgo(0), daysAgo(1), daysAgo(3), daysAgo(4)]
        #expect(streak.currentStreak(from: dates, now: today) == 2)
    }

    @Test("Nothing recent means no streak")
    func staleHistory() {
        #expect(streak.currentStreak(from: [daysAgo(5), daysAgo(6)], now: today) == 0)
    }

    @Test("Several sessions in one day are still one day")
    func multiplePerDay() {
        let dates = [
            today, today.addingTimeInterval(-3600), today.addingTimeInterval(-7200),
            daysAgo(1),
        ]
        #expect(streak.currentStreak(from: dates, now: today) == 2)
    }

    @Test("No history is zero, not a crash")
    func empty() {
        #expect(streak.currentStreak(from: [], now: today) == 0)
        #expect(streak.longestStreak(from: []) == 0)
    }

    @Test("The longest run is found even when it is not the current one")
    func longest() {
        let dates = [
            daysAgo(10), daysAgo(9), daysAgo(8), daysAgo(7),  // a run of 4
            daysAgo(1), daysAgo(0),                            // a run of 2
        ]
        #expect(streak.longestStreak(from: dates) == 4)
        #expect(streak.currentStreak(from: dates, now: today) == 2)
    }
}

@Suite("Handoff")
struct HandoffTests {
    private let serverID = UUID()

    @Test("A payload survives the trip between devices")
    func roundTrip() throws {
        let payload = HandoffActivity.Payload(
            serverID: serverID, itemID: "li-1", position: 1234.5, title: "A Book"
        )
        let decoded = try #require(HandoffActivity.payload(from: HandoffActivity.userInfo(for: payload)))
        #expect(decoded == payload)
    }

    @Test("Position and title are optional")
    func minimalPayload() throws {
        let payload = HandoffActivity.Payload(serverID: serverID, itemID: "li-1")
        let info = HandoffActivity.userInfo(for: payload)
        #expect(info["position"] == nil)
        let decoded = try #require(HandoffActivity.payload(from: info))
        #expect(decoded.position == nil)
    }

    @Test("Anything malformed is refused rather than half-understood")
    func rejectsMalformed() {
        // Opening the wrong book is worse than not opening one.
        #expect(HandoffActivity.payload(from: nil) == nil)
        #expect(HandoffActivity.payload(from: [:]) == nil)
        #expect(HandoffActivity.payload(from: ["itemID": "li-1"]) == nil)
        #expect(HandoffActivity.payload(from: ["serverID": "not-a-uuid", "itemID": "li-1"]) == nil)
        #expect(HandoffActivity.payload(from: ["serverID": serverID.uuidString, "itemID": ""]) == nil)
    }

    @Test("A nonsense position is dropped, not carried")
    func rejectsBadPosition() throws {
        let info: [String: Any] = [
            "serverID": serverID.uuidString, "itemID": "li-1", "position": -5.0,
        ]
        #expect(try #require(HandoffActivity.payload(from: info)).position == nil)

        let infinite: [String: Any] = [
            "serverID": serverID.uuidString, "itemID": "li-1", "position": Double.infinity,
        ]
        #expect(try #require(HandoffActivity.payload(from: infinite)).position == nil)
    }

    @Test("The activity type matches what the app declares in its Info.plist")
    func declaredInInfoPlist() throws {
        // An undeclared type is silently ignored by the system, which looks
        // exactly like handoff being broken.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let types = try #require(plist["NSUserActivityTypes"] as? [String])
        #expect(types.contains(HandoffActivity.itemType))
    }

    @Test("Live Activities are declared too")
    func liveActivitiesDeclared() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "App/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["NSSupportsLiveActivities"] as? Bool == true)
    }
}

@Suite("Live Activity state")
struct PlaybackActivityStateTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("The finish time is what lets the Island count itself down")
    func projectedFinish() {
        // Pushing a number every second would get the activity throttled.
        let state = PlaybackActivityAttributes.ContentState(
            position: 600, duration: 3600, isPlaying: true, updatedAt: start
        )
        #expect(state.timeRemaining == 3000)
        #expect(state.projectedFinish == start.addingTimeInterval(3000))
    }

    @Test("Progress is a fraction, clamped")
    func fraction() {
        let half = PlaybackActivityAttributes.ContentState(
            position: 1800, duration: 3600, isPlaying: true
        )
        #expect(half.fraction == 0.5)

        let overrun = PlaybackActivityAttributes.ContentState(
            position: 9999, duration: 3600, isPlaying: false
        )
        #expect(overrun.fraction == 1)
        #expect(overrun.timeRemaining == 0)
    }
}
