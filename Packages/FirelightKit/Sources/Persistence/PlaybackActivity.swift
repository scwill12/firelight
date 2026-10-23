import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// What the Live Activity and the Dynamic Island show.
///
/// Lives here rather than in `PlaybackKit` because the widget extension has to
/// see the same type to render it, and the extension already links
/// `Persistence`. The attributes are what never changes for a listen; the
/// content state is what ticks.
public struct PlaybackActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var chapterTitle: String?
        /// Seconds into the book.
        public var position: TimeInterval
        public var duration: TimeInterval
        public var isPlaying: Bool
        /// Lets the Island show a live countdown without an update per second.
        public var updatedAt: Date

        public init(
            chapterTitle: String? = nil,
            position: TimeInterval,
            duration: TimeInterval,
            isPlaying: Bool,
            updatedAt: Date = .now
        ) {
            self.chapterTitle = chapterTitle
            self.position = position
            self.duration = duration
            self.isPlaying = isPlaying
            self.updatedAt = updatedAt
        }

        public var fraction: Double {
            guard duration > 0 else { return 0 }
            return min(max(position / duration, 0), 1)
        }

        public var timeRemaining: TimeInterval { max(0, duration - position) }

        /// The moment playback would reach the end at the current rate, so the
        /// Island can render a `Text(timerInterval:)` that counts itself down
        /// instead of needing an update every second.
        public var projectedFinish: Date {
            updatedAt.addingTimeInterval(timeRemaining)
        }
    }

    public var itemID: String
    public var title: String
    public var author: String?

    public init(itemID: String, title: String, author: String? = nil) {
        self.itemID = itemID
        self.title = title
        self.author = author
    }
}
#endif
