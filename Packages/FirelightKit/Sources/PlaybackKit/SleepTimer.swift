import Foundation

public enum SleepTimerMode: Sendable, Hashable, Codable {
    case off
    /// A fixed length from when it was set.
    case duration(TimeInterval)
    /// Stops when the current chapter does.
    case endOfChapter

    public static let durationOptions: [TimeInterval] = [
        5 * 60, 10 * 60, 15 * 60, 30 * 60, 45 * 60, 60 * 60, 90 * 60,
    ]
}

/// Works out how long is left on the sleep timer and how loud to be.
///
/// Pure: the ticking lives in the controller, the rules live here where they
/// can be tested without waiting an hour.
public struct SleepTimerCalculator: Sendable, Hashable {
    /// The volume ramps down over the last stretch, so sleep isn't ended by a
    /// sudden silence.
    public var fadeDuration: TimeInterval
    /// Shake-to-extend adds this much.
    public var extendBy: TimeInterval

    public init(fadeDuration: TimeInterval = 30, extendBy: TimeInterval = 5 * 60) {
        self.fadeDuration = fadeDuration
        self.extendBy = extendBy
    }

    /// Seconds remaining, or nil when no timer is running.
    ///
    /// For an end-of-chapter timer the answer depends on the playback rate:
    /// at 2× a ten-minute chapter has five minutes of real time left.
    public func remaining(
        mode: SleepTimerMode,
        endsAt: Date?,
        now: Date,
        position: TimeInterval,
        chapterEnd: TimeInterval?,
        rate: PlaybackRate
    ) -> TimeInterval? {
        switch mode {
        case .off:
            return nil
        case .duration:
            guard let endsAt else { return nil }
            return max(0, endsAt.timeIntervalSince(now))
        case .endOfChapter:
            guard let chapterEnd, chapterEnd > position else { return 0 }
            return (chapterEnd - position) / max(rate.value, 0.01)
        }
    }

    /// 1.0 normally, ramping to 0 across the last `fadeDuration` seconds.
    public func volumeMultiplier(remaining: TimeInterval?) -> Double {
        guard let remaining else { return 1 }
        guard remaining < fadeDuration else { return 1 }
        guard fadeDuration > 0 else { return 0 }
        return min(max(remaining / fadeDuration, 0), 1)
    }

    public func hasExpired(remaining: TimeInterval?) -> Bool {
        guard let remaining else { return false }
        return remaining <= 0
    }

    /// Extending a fixed timer pushes its end back; extending an
    /// end-of-chapter timer converts it to a fixed one, because "one more
    /// chapter" is a different request from "a bit longer".
    public func extended(mode: SleepTimerMode, endsAt: Date?, now: Date) -> (mode: SleepTimerMode, endsAt: Date?) {
        switch mode {
        case .off:
            return (.off, nil)
        case .duration(let total):
            let base = max(endsAt ?? now, now)
            return (.duration(total + extendBy), base.addingTimeInterval(extendBy))
        case .endOfChapter:
            return (.duration(extendBy), now.addingTimeInterval(extendBy))
        }
    }
}
