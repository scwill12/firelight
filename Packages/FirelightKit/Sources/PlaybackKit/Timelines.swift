import ABSKit
import Foundation

/// Spelled out so `TrackTimeline` need not nest inside the engine.
public typealias AudioEngineResolvedTrack = AudioEngine.ResolvedTrack

/// Maps between a position in the book and a position in one of its files.
///
/// An audiobook is usually many files. The player works in *book* time —
/// that is what the scrubber shows, what chapters are measured in and what
/// syncs to the server — and this converts to and from the per-file time that
/// AVFoundation needs. Getting this wrong puts every chapter mark after the
/// first file in the wrong place.
public struct TrackTimeline: Sendable, Hashable {
    public struct Location: Sendable, Hashable {
        /// Index into `tracks`, not the server's `index` field.
        public let trackIndex: Int
        /// Seconds into that file.
        public let timeInTrack: TimeInterval
    }

    public let tracks: [ABSAudioTrack]
    public let totalDuration: TimeInterval

    public init(tracks: [ABSAudioTrack]) {
        let ordered = tracks.sorted { $0.offset < $1.offset }
        self.tracks = ordered
        // Prefer the last track's offset + length; falling back to a sum keeps
        // a session with missing offsets usable.
        if let last = ordered.last {
            self.totalDuration = max(last.offset + last.length, ordered.reduce(0) { $0 + $1.length })
        } else {
            self.totalDuration = 0
        }
    }

    /// Builds a timeline from tracks already resolved to playable URLs, which
    /// is how a downloaded book is played.
    public init(resolved: [AudioEngineResolvedTrack]) {
        let ordered = resolved.sorted { $0.offset < $1.offset }
        self.tracks = ordered.map {
            ABSAudioTrack(index: nil, startOffset: $0.offset, duration: $0.duration,
                          title: nil, contentUrl: $0.url.absoluteString, mimeType: nil, codec: nil)
        }
        if let last = ordered.last {
            self.totalDuration = max(last.offset + last.duration, ordered.reduce(0) { $0 + $1.duration })
        } else {
            self.totalDuration = 0
        }
    }

    public var isEmpty: Bool { tracks.isEmpty }

    /// Book time -> which file, and where in it.
    public func location(forBookTime bookTime: TimeInterval) -> Location? {
        guard !tracks.isEmpty else { return nil }
        let clamped = min(max(bookTime, 0), max(totalDuration, 0))

        // Last track whose offset is at or before the target.
        var index = 0
        for (candidate, track) in tracks.enumerated() where track.offset <= clamped + 0.0001 {
            index = candidate
        }
        let track = tracks[index]
        let timeInTrack = min(max(clamped - track.offset, 0), max(track.length, 0))
        return Location(trackIndex: index, timeInTrack: timeInTrack)
    }

    /// Which file, and where in it -> book time.
    public func bookTime(forTrackIndex index: Int, timeInTrack: TimeInterval) -> TimeInterval {
        guard tracks.indices.contains(index) else { return 0 }
        return tracks[index].offset + max(0, timeInTrack)
    }

    public func track(at index: Int) -> ABSAudioTrack? {
        tracks.indices.contains(index) ? tracks[index] : nil
    }
}

/// Where the listener is in the book's chapters.
public struct ChapterTimeline: Sendable, Hashable {
    public let chapters: [ABSChapter]

    public init(chapters: [ABSChapter]) {
        self.chapters = chapters.sorted { $0.start < $1.start }
    }

    public var isEmpty: Bool { chapters.isEmpty }

    public func chapter(at time: TimeInterval) -> ABSChapter? {
        guard !chapters.isEmpty else { return nil }
        if let match = chapters.last(where: { $0.start <= time + 0.0001 }) {
            // Past the end of the last chapter still reads as that chapter.
            return match
        }
        return chapters.first
    }

    public func index(at time: TimeInterval) -> Int? {
        guard let chapter = chapter(at: time) else { return nil }
        return chapters.firstIndex(of: chapter)
    }

    /// Progress through the current chapter, 0...1.
    public func chapterProgress(at time: TimeInterval) -> Double {
        guard let chapter = chapter(at: time), chapter.duration > 0 else { return 0 }
        return min(max((time - chapter.start) / chapter.duration, 0), 1)
    }

    /// Where "next chapter" goes.
    public func startOfNextChapter(after time: TimeInterval) -> TimeInterval? {
        chapters.first { $0.start > time + 0.5 }?.start
    }

    /// Where "previous chapter" goes.
    ///
    /// Within the first few seconds of a chapter it goes to the previous one;
    /// after that it restarts the current chapter, which is what every other
    /// player does and what people expect.
    public func startOfPreviousChapter(from time: TimeInterval, restartThreshold: TimeInterval = 3) -> TimeInterval? {
        guard let current = chapter(at: time) else { return nil }
        if time - current.start > restartThreshold { return current.start }
        guard let index = chapters.firstIndex(of: current), index > 0 else { return current.start }
        return chapters[index - 1].start
    }

    public func endOfChapter(at time: TimeInterval) -> TimeInterval? {
        chapter(at: time)?.end
    }

    /// True when `from` and `to` are in different chapters — the cue for a
    /// haptic and for a progress sync.
    public func crossesBoundary(from: TimeInterval, to: TimeInterval) -> Bool {
        guard !chapters.isEmpty else { return false }
        return index(at: from) != index(at: to)
    }
}

/// What the player's clock counts against: the whole book, or just the
/// chapter you are in.
///
/// Pure, because the rule that matters is the fallback. A chapter clock is
/// only meaningful when there *is* a chapter with a length — a book with no
/// chapter marks would otherwise show a clock frozen at zero, which is worse
/// than the book clock the reader was trying to replace.
public struct TimeScope: Sendable, Hashable {
    /// Where the clock starts counting, in book time.
    public let start: TimeInterval
    /// How much book time it runs for.
    public let duration: TimeInterval

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.duration = duration
    }

    public static func resolve(
        display: TimeDisplay,
        chapters: ChapterTimeline,
        position: TimeInterval,
        bookDuration: TimeInterval
    ) -> TimeScope {
        guard display == .chapter,
              let chapter = chapters.chapter(at: position),
              chapter.duration > 0
        else { return TimeScope(start: 0, duration: bookDuration) }
        return TimeScope(start: chapter.start, duration: chapter.duration)
    }

    public func elapsed(at position: TimeInterval) -> TimeInterval {
        max(0, position - start)
    }

    public func remaining(at position: TimeInterval) -> TimeInterval {
        max(0, start + duration - position)
    }

    /// Progress through the scope, 0...1.
    public func fraction(at position: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: position) / duration, 0), 1)
    }
}
