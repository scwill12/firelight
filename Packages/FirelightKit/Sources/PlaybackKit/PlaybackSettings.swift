import Foundation

/// Playback speed, kept to the steps the UI offers.
///
/// 0.5× to 3.5× in 0.05 steps, per the spec. A struct rather than a `Double`
/// so a speed can never be set to something the UI cannot represent or the
/// engine cannot honour.
public struct PlaybackRate: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public static let minimum: Double = 0.5
    public static let maximum: Double = 3.5
    public static let step: Double = 0.05
    public static let normal = PlaybackRate(1.0)

    public let value: Double

    public init(_ value: Double) {
        let clamped = min(max(value, Self.minimum), Self.maximum)
        // Snap to the step grid, then round away floating-point dust so that
        // 1.2000000000000002 never reaches the UI or the engine.
        let snapped = (clamped / Self.step).rounded() * Self.step
        self.value = (snapped * 100).rounded() / 100
    }

    public func stepped(by steps: Int) -> PlaybackRate {
        PlaybackRate(value + Double(steps) * Self.step)
    }

    public static func < (lhs: PlaybackRate, rhs: PlaybackRate) -> Bool { lhs.value < rhs.value }

    /// "1×", "1.5×", "1.05×" — never "1.0×".
    public var description: String {
        let text = value == value.rounded()
            ? String(Int(value))
            : String(format: value * 10 == (value * 10).rounded() ? "%.1f" : "%.2f", value)
        return "\(text)×"
    }

    /// The speeds the player offers as one-tap presets.
    public static let presets: [PlaybackRate] = [
        PlaybackRate(0.8), PlaybackRate(1.0), PlaybackRate(1.2),
        PlaybackRate(1.5), PlaybackRate(1.75), PlaybackRate(2.0),
    ]
}

/// Whether the player's clock is measured against the chapter or the book.
///
/// Both are the right answer at different moments: "how long until I can stop"
/// is a chapter question, "how much of this book is left" is a book question.
/// Audiobook players that offer only the second one make the first unanswerable.
public enum TimeDisplay: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// Elapsed and remaining across the whole book.
    case book
    /// Elapsed and remaining within the current chapter.
    case chapter

    public static let `default` = TimeDisplay.book

    public var id: String { rawValue }
}

/// Whether to add a Live Activity on top of the system's Now Playing control.
///
/// Off by default, and the reason is worth stating: iOS already draws a Now
/// Playing control on the lock screen and in the Dynamic Island for *any*
/// audio app, with artwork, a scrubber and an AirPlay picker. A Live Activity
/// showing the same book is a second set of transport controls for one piece
/// of audio — which is what it looks like on the lock screen, and what Apple's
/// own guidance steers away from.
///
/// It stays available because some people prefer its larger buttons, but
/// nobody should have to turn it off to get one control instead of two.
public enum LiveActivityPreference: String, Sendable, Hashable, Codable, CaseIterable {
    case off
    case on

    public static let `default` = LiveActivityPreference.off

    public var isOn: Bool { self == .on }
}

/// How far the skip buttons jump.
public struct SkipInterval: Sendable, Hashable, Codable {
    public static let options: [TimeInterval] = [5, 10, 15, 20, 30, 45, 60, 90]
    public static let `default` = SkipInterval(backward: 15, forward: 30)

    public var backward: TimeInterval
    public var forward: TimeInterval

    public init(backward: TimeInterval, forward: TimeInterval) {
        self.backward = backward
        self.forward = forward
    }
}

/// Rewinds a little when you come back, more when you have been away longer.
///
/// The point is to re-establish context: a few seconds covers "I paused to
/// park the car", a longer one covers "I paused yesterday". A ladder rather
/// than a formula because the steps are what a user can reason about and set.
public struct SmartRewind: Sendable, Hashable, Codable {
    public struct Threshold: Sendable, Hashable, Codable {
        /// Applies when the pause was at least this long.
        public let pausedAtLeast: TimeInterval
        public let rewind: TimeInterval

        public init(pausedAtLeast: TimeInterval, rewind: TimeInterval) {
            self.pausedAtLeast = pausedAtLeast
            self.rewind = rewind
        }
    }

    public var isEnabled: Bool
    /// Ordered shortest pause first.
    public var thresholds: [Threshold]

    public static let `default` = SmartRewind(
        isEnabled: true,
        thresholds: [
            Threshold(pausedAtLeast: 10, rewind: 2),
            Threshold(pausedAtLeast: 60, rewind: 5),
            Threshold(pausedAtLeast: 30 * 60, rewind: 10),
            Threshold(pausedAtLeast: 6 * 3600, rewind: 20),
            Threshold(pausedAtLeast: 24 * 3600, rewind: 30),
        ]
    )

    public init(isEnabled: Bool, thresholds: [Threshold]) {
        self.isEnabled = isEnabled
        self.thresholds = thresholds.sorted { $0.pausedAtLeast < $1.pausedAtLeast }
    }

    /// Seconds to rewind after a pause of this length. Zero for a brief pause:
    /// nobody wants their place moved because they tapped pause and play.
    public func rewind(forPauseDuration pause: TimeInterval) -> TimeInterval {
        guard isEnabled, pause > 0 else { return 0 }
        return thresholds.last { pause >= $0.pausedAtLeast }?.rewind ?? 0
    }
}
