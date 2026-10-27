import Foundation
import Testing
@testable import SyncEngine

@Suite("Listening sessions")
struct ListeningSessionTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private let builder = ListeningSessionBuilder()

    private func entry(
        minutes: Double,
        position: TimeInterval,
        sessionID: String? = nil,
        device: String = "iPhone",
        listened: Double = 0,
        isFinished: Bool = false
    ) -> ProgressJournalEntry {
        ProgressJournalEntry(
            id: UUID(),
            serverID: UUID(),
            position: ProgressPosition(
                itemID: "book",
                currentTime: position,
                duration: 36_000,
                isFinished: isFinished,
                updatedAt: start.addingTimeInterval(minutes * 60),
                deviceID: "device-\(device)",
                deviceLabel: device
            ),
            origin: .local,
            syncState: .synced,
            recordedAt: start.addingTimeInterval(minutes * 60),
            attemptCount: 0,
            sessionID: sessionID,
            timeListening: listened
        )
    }

    @Test("A continuous run becomes one session")
    func continuousRunIsOneSession() throws {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            entry(minutes: 5, position: 300),
            entry(minutes: 10, position: 600),
        ])
        let only = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(only.startPosition == 0)
        #expect(only.endPosition == 600)
        #expect(only.secondsListened == 600)
        #expect(only.elapsed == 600)
    }

    @Test("A long gap splits one run into two sessions")
    func gapSplitsSessions() {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            entry(minutes: 10, position: 600),
            // Picked up again two hours later.
            entry(minutes: 130, position: 600),
            entry(minutes: 140, position: 1_200),
        ])
        #expect(sessions.count == 2)
    }

    @Test("A gap just inside the threshold stays one session")
    func shortGapDoesNotSplit() {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            entry(minutes: 10, position: 600),
            entry(minutes: 39, position: 600),
            entry(minutes: 45, position: 960),
        ])
        #expect(sessions.count == 1)
    }

    @Test("Two recorded session ids never merge, however close in time")
    func sessionIDsNeverMerge() {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0, sessionID: "a", listened: 300),
            entry(minutes: 5, position: 300, sessionID: "a", listened: 300),
            // One minute later, but the player called it a new session.
            entry(minutes: 6, position: 300, sessionID: "b", listened: 240),
            entry(minutes: 10, position: 540, sessionID: "b", listened: 240),
        ])
        #expect(sessions.count == 2)
    }

    @Test("Reopening a finished book is not a listen, whatever the total says")
    func staleTotalDoesNotInventListening() {
        // Regression. `timeListening` is a running total that outlives the
        // stretch it was counted in, so an entry written when the book was
        // merely reopened at the end carried the previous session's 59
        // seconds. Measured by movement, this is what it is: nothing.
        #expect(builder.sessions(from: [
            entry(minutes: 0, position: 59, sessionID: "b", listened: 59),
            entry(minutes: 1, position: 59, sessionID: "b", listened: 59),
        ]).isEmpty)
    }

    @Test("Listening is measured by how far the position moved")
    func fallsBackToMeasuring() throws {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            entry(minutes: 10, position: 600),
        ])
        #expect(try #require(sessions.first).secondsListened == 600)
    }

    @Test("Seeking backwards is not listening")
    func backwardsIsNotListening() throws {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 600),
            entry(minutes: 5, position: 300),
            entry(minutes: 10, position: 600),
        ])
        // Only the second leg counts: 300s back is a seek, 300s forward is real.
        #expect(try #require(sessions.first).secondsListened == 300)
    }

    @Test("Skipping faster than 4x is not listening")
    func skippingIsNotListening() {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            // An hour of book in one minute: a skip, not listening.
            entry(minutes: 1, position: 3_600),
        ])
        #expect(sessions.isEmpty)
    }

    @Test("A book opened but not listened to is not a session")
    func openedButNotListenedIsDropped() {
        #expect(builder.sessions(from: [entry(minutes: 0, position: 300)]).isEmpty)
        #expect(builder.sessions(from: [
            entry(minutes: 0, position: 300),
            entry(minutes: 2, position: 300),
        ]).isEmpty)
    }

    @Test("Every device that contributed is listed, once, in order")
    func listsContributingDevices() throws {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0, device: "iPhone"),
            entry(minutes: 5, position: 300, device: "iPhone"),
            entry(minutes: 10, position: 600, device: "iPad"),
        ])
        #expect(try #require(sessions.first).deviceLabels == ["iPhone", "iPad"])
    }

    @Test("Finishing the book marks the session it happened in")
    func marksTheSessionThatFinishedIt() throws {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            entry(minutes: 10, position: 600, isFinished: true),
        ])
        #expect(try #require(sessions.first).finishedHere)
    }

    @Test("Sessions come back newest first")
    func newestFirst() {
        let sessions = builder.sessions(from: [
            entry(minutes: 0, position: 0),
            entry(minutes: 10, position: 600),
            entry(minutes: 200, position: 600),
            entry(minutes: 210, position: 1_200),
        ])
        #expect(sessions.count == 2)
        #expect(sessions[0].startedAt > sessions[1].startedAt)
    }

    @Test("Entries with no audio position are ignored, not crashed on")
    func ignoresEbookOnlyEntries() {
        var ebook = entry(minutes: 0, position: 0)
        ebook.position.currentTime = nil
        #expect(builder.sessions(from: [ebook]).isEmpty)
    }

    @Test("No entries is no sessions")
    func emptyInput() {
        #expect(builder.sessions(from: []).isEmpty)
    }
}
