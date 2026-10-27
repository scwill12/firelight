import Foundation

/// One stretch of listening: when it started, when it stopped, and how much
/// of the book went by in between.
///
/// This is what someone means by "my history". A list of positions answers
/// "where was I?"; a list of sessions answers "when did I listen, and for how
/// long?" — which is the question people actually ask of a book they have been
/// reading for a fortnight.
public struct ListeningSession: Sendable, Hashable, Identifiable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    /// Where the book was when this stretch began and ended.
    public let startPosition: TimeInterval
    public let endPosition: TimeInterval
    /// Time actually listened, which is not the same as `endedAt - startedAt`:
    /// a book left paused is not listening, and 2× covers more book than
    /// seconds elapsed.
    public let secondsListened: TimeInterval
    /// Every device that contributed, in the order they first appear.
    public let deviceLabels: [String]
    /// True when the book was finished during this stretch.
    public let finishedHere: Bool

    /// How long the listener was actually at it, wall-clock.
    public var elapsed: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

/// Turns the progress journal into sessions.
///
/// Two ways to decide where one stretch ends and the next begins, in order of
/// preference:
///
/// 1. **`sessionID`.** Entries written during one uninterrupted listen already
///    carry one, because the server needs the same grouping. When it is there
///    it is authoritative — it knows about a pause that the clock cannot see.
/// 2. **A gap in the clock.** Entries from another device, or from before
///    sessions were recorded, have no id. Thirty minutes is the same
///    threshold `ListeningStatsCalculator` uses, deliberately: two different
///    answers to "was that one listen?" in one app would be a bug.
public struct ListeningSessionBuilder: Sendable {
    private let maximumGap: TimeInterval

    public init(maximumGap: TimeInterval = 30 * 60) {
        self.maximumGap = maximumGap
    }

    public func sessions(from entries: [ProgressJournalEntry]) -> [ListeningSession] {
        let ordered = entries
            .filter { $0.position.currentTime != nil }
            .sorted { $0.position.updatedAt < $1.position.updatedAt }
        guard !ordered.isEmpty else { return [] }

        var groups: [[ProgressJournalEntry]] = []
        var current: [ProgressJournalEntry] = []

        for entry in ordered {
            guard let previous = current.last else {
                current = [entry]
                continue
            }
            if belongsWithPrevious(entry, previous: previous) {
                current.append(entry)
            } else {
                groups.append(current)
                current = [entry]
            }
        }
        groups.append(current)

        // A stretch where the position never moved is the book being opened,
        // not listened to. Saying "0s" on its own row is noise.
        return groups.compactMap(session(from:)).filter { $0.secondsListened > 0 }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func belongsWithPrevious(
        _ entry: ProgressJournalEntry,
        previous: ProgressJournalEntry
    ) -> Bool {
        // Two different recorded sessions are never one stretch, however close
        // together they sit.
        if let a = entry.sessionID, let b = previous.sessionID { return a == b }
        if (entry.sessionID == nil) != (previous.sessionID == nil) { return false }

        let gap = entry.position.updatedAt.timeIntervalSince(previous.position.updatedAt)
        return gap >= 0 && gap <= maximumGap
    }

    private func session(from group: [ProgressJournalEntry]) -> ListeningSession? {
        guard let first = group.first, let last = group.last,
              let startPosition = first.position.currentTime,
              let endPosition = last.position.currentTime
        else { return nil }

        var devices: [String] = []
        for entry in group where !devices.contains(entry.position.deviceLabel) {
            devices.append(entry.position.deviceLabel)
        }

        return ListeningSession(
            id: first.sessionID ?? first.id.uuidString,
            startedAt: first.position.updatedAt,
            endedAt: last.position.updatedAt,
            startPosition: startPosition,
            endPosition: endPosition,
            secondsListened: secondsListened(in: group),
            deviceLabels: devices,
            finishedHere: group.contains { $0.position.isFinished }
        )
    }

    /// The recorded total when there is one, because the player counted it as
    /// it went and knows about pauses. Otherwise measured from how far the
    /// position moved, under the same rules the statistics use: backwards is
    /// a seek, and faster than 4× is a skip.
    private func secondsListened(in group: [ProgressJournalEntry]) -> TimeInterval {
        let recorded = group.map(\.timeListening).max() ?? 0
        if recorded > 0 { return recorded }

        var total: TimeInterval = 0
        for (previous, entry) in zip(group, group.dropFirst()) {
            guard let from = previous.position.currentTime,
                  let to = entry.position.currentTime
            else { continue }
            let elapsed = entry.position.updatedAt.timeIntervalSince(previous.position.updatedAt)
            let advanced = to - from
            guard elapsed > 0, advanced > 0, advanced <= elapsed * 4 else { continue }
            total += advanced
        }
        return total
    }
}
