import Foundation

/// Estimates how long is left, from how fast this reader actually reads.
///
/// A fixed words-per-minute figure is wrong for almost everyone. Measuring the
/// reader's own pace is the only way "18 minutes left in this chapter" means
/// anything — and until there is enough evidence, it says nothing rather than
/// guessing.
public struct ReadingSpeedEstimator: Sendable, Hashable {
    /// One observation: how far through the book, and when.
    public struct Sample: Sendable, Hashable {
        public let fraction: Double
        public let at: Date

        public init(fraction: Double, at: Date) {
            self.fraction = fraction
            self.at = at
        }
    }

    /// Ignore gaps longer than this: the reader put the book down.
    public var maximumGap: TimeInterval
    /// Below this, there is not enough evidence to claim a speed.
    public var minimumSamples: Int
    /// Sanity bounds, in words per minute.
    public var plausibleRange: ClosedRange<Double>

    public init(
        maximumGap: TimeInterval = 5 * 60,
        minimumSamples: Int = 4,
        plausibleRange: ClosedRange<Double> = 60...800
    ) {
        self.maximumGap = maximumGap
        self.minimumSamples = minimumSamples
        self.plausibleRange = plausibleRange
    }

    /// Words per minute, or nil when there is not enough to go on.
    public func wordsPerMinute(from samples: [Sample], totalWords: Int) -> Double? {
        guard totalWords > 0, samples.count >= minimumSamples else { return nil }
        let ordered = samples.sorted { $0.at < $1.at }

        var wordsRead = 0.0
        var secondsSpent = 0.0
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            let gap = current.at.timeIntervalSince(previous.at)
            // Skip the gaps where the book was closed, and any backwards jump.
            guard gap > 0, gap <= maximumGap else { continue }
            let advanced = current.fraction - previous.fraction
            guard advanced > 0 else { continue }
            wordsRead += advanced * Double(totalWords)
            secondsSpent += gap
        }

        guard secondsSpent > 0, wordsRead > 0 else { return nil }
        let speed = wordsRead / (secondsSpent / 60)
        return plausibleRange.contains(speed) ? speed : nil
    }

    /// Seconds left, given a speed. Nil when the speed is unknown.
    public func timeRemaining(
        fraction: Double,
        totalWords: Int,
        wordsPerMinute: Double?
    ) -> TimeInterval? {
        guard let wordsPerMinute, wordsPerMinute > 0, totalWords > 0 else { return nil }
        let remainingWords = Double(totalWords) * max(0, 1 - min(max(fraction, 0), 1))
        return remainingWords / wordsPerMinute * 60
    }
}
