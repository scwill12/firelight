import Foundation
import Persistence

/// How much was listened to, and when.
///
/// Computed from the progress journal rather than asked of the server: the
/// journal is what this device actually did, it is there offline, and ABS's
/// own statistics count differently enough that mixing the two would produce
/// numbers that never quite agree.
public struct ListeningStats: Sendable, Hashable {
    public struct Day: Sendable, Hashable, Identifiable {
        public let date: Date
        /// Seconds listened on that day.
        public let seconds: TimeInterval
        public var id: Date { date }
    }

    public let days: [Day]
    public let totalSeconds: TimeInterval
    public let currentStreak: Int
    public let longestStreak: Int
    public let itemsFinished: Int

    public var totalHours: Double { totalSeconds / 3600 }

    /// The busiest day, for the Year in Books card.
    public var bestDay: Day? { days.max { $0.seconds < $1.seconds } }

    public var averageSecondsPerActiveDay: TimeInterval {
        let active = days.filter { $0.seconds > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.seconds } / Double(active.count)
    }
}

/// Turns journal entries into statistics.
///
/// Pure, so the arithmetic — which is the whole feature — is testable without
/// a database or a year of waiting.
public struct ListeningStatsCalculator: Sendable {
    /// A single observation: how far through, and when.
    public struct Sample: Sendable, Hashable {
        public let itemID: String
        public let position: TimeInterval
        public let at: Date
        public let isFinished: Bool

        public init(itemID: String, position: TimeInterval, at: Date, isFinished: Bool = false) {
            self.itemID = itemID
            self.position = position
            self.at = at
            self.isFinished = isFinished
        }
    }

    private let calendar: Calendar
    /// Gaps longer than this are the book being put down, not listening.
    private let maximumGap: TimeInterval

    public init(calendar: Calendar = .current, maximumGap: TimeInterval = 30 * 60) {
        self.calendar = calendar
        self.maximumGap = maximumGap
    }

    public func stats(from samples: [Sample], in range: ClosedRange<Date>) -> ListeningStats {
        let inRange = samples.filter { range.contains($0.at) }.sorted { $0.at < $1.at }

        var secondsByDay: [Date: TimeInterval] = [:]
        var finished = Set<String>()

        // Listening is measured by how far the position moved, not by wall
        // clock: a book left paused for an hour is not an hour of listening,
        // and one played at 2× covers more book than seconds elapsed.
        var lastByItem: [String: Sample] = [:]
        for sample in inRange {
            if sample.isFinished { finished.insert(sample.itemID) }

            defer { lastByItem[sample.itemID] = sample }
            guard let previous = lastByItem[sample.itemID] else { continue }

            let elapsed = sample.at.timeIntervalSince(previous.at)
            guard elapsed > 0, elapsed <= maximumGap else { continue }

            let advanced = sample.position - previous.position
            // Backwards is a seek, not listening. Forwards by more than the
            // time elapsed at 4× is a skip, not listening either.
            guard advanced > 0, advanced <= elapsed * 4 else { continue }

            let day = calendar.startOfDay(for: sample.at)
            secondsByDay[day, default: 0] += advanced
        }

        let days = secondsByDay
            .map { ListeningStats.Day(date: $0.key, seconds: $0.value) }
            .sorted { $0.date < $1.date }

        let streak = ListeningStreak(calendar: calendar)
        let activeDates = days.filter { $0.seconds > 0 }.map(\.date)

        return ListeningStats(
            days: days,
            totalSeconds: days.reduce(0) { $0 + $1.seconds },
            currentStreak: streak.currentStreak(from: activeDates, now: range.upperBound),
            longestStreak: streak.longestStreak(from: activeDates),
            itemsFinished: finished.count
        )
    }

    /// Convenience ranges for the stats screen.
    public func range(for period: Period, now: Date = .now) -> ClosedRange<Date> {
        let end = now
        let start: Date
        switch period {
        case .week:
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        case .month:
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        case .year:
            start = calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now)) ?? now
        case .calendarYear(let year):
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            start = calendar.date(from: components) ?? now
            var endComponents = DateComponents()
            endComponents.year = year
            endComponents.month = 12
            endComponents.day = 31
            endComponents.hour = 23
            endComponents.minute = 59
            return start...(calendar.date(from: endComponents) ?? now)
        }
        return start...end
    }

    public enum Period: Sendable, Hashable {
        case week
        case month
        case year
        case calendarYear(Int)
    }
}

/// Decides whether the Year in Books recap is available.
///
/// December only, as the spec says — a year-in-review in March is a review of
/// nothing.
public enum YearInBooks {
    public static func isAvailable(on date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.component(.month, from: date) == 12
    }

    public static func year(on date: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date)
    }
}
