import ABSKit
import AVFoundation
import Foundation
import Observation

/// Wraps AVFoundation and speaks in *book* time.
///
/// A book is many files, so the queue is rebuilt from whichever track a seek
/// lands in, and every position that leaves this type has the track's
/// `startOffset` already folded in. Nothing above this layer needs to know
/// that files exist.
@MainActor
@Observable
public final class AudioEngine {
    public private(set) var state: PlaybackState = .idle
    /// Seconds into the book.
    public private(set) var position: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isBuffering = false

    /// Set when playback failed, for the UI to show.
    public private(set) var failure: String?

    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var timeline = TrackTimeline(tracks: [])
    @ObservationIgnored private var currentTrackIndex = 0
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?

    /// Called on every tick, with book time. The controller uses it to sync
    /// progress, fire haptics at chapter marks and run the sleep timer.
    public var onPositionChange: (@MainActor (TimeInterval) -> Void)?
    /// Called when the book finishes.
    public var onFinished: (@MainActor () -> Void)?

    public init() {
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
    }

    // MARK: - Loading

    /// One track, already resolved to something playable — a streaming URL or
    /// a file on disk. The engine does not care which, which is what makes
    /// offline playback the same code path as streaming.
    public struct ResolvedTrack: Sendable, Hashable {
        public let url: URL
        public let offset: TimeInterval
        public let duration: TimeInterval

        public init(url: URL, offset: TimeInterval, duration: TimeInterval) {
            self.url = url
            self.offset = offset
            self.duration = duration
        }
    }

    /// Prepares tracks for playback without starting them.
    public func load(
        tracks: [ResolvedTrack],
        duration totalDuration: TimeInterval,
        startingAt bookTime: TimeInterval
    ) {
        resolvedTracks = tracks.sorted { $0.offset < $1.offset }
        timeline = TrackTimeline(resolved: resolvedTracks)
        duration = totalDuration > 0 ? totalDuration : timeline.totalDuration
        failure = nil

        guard !resolvedTracks.isEmpty else {
            state = .failed
            failure = "This item has no audio files."
            return
        }

        state = .loading
        rebuildQueue(startingAtBookTime: bookTime)
    }

    /// Streams a server session.
    public func load(
        session: ABSPlaybackSession,
        baseURL: URL,
        accessToken: String?,
        startingAt bookTime: TimeInterval
    ) {
        let tracks = session.orderedTracks.compactMap { track -> ResolvedTrack? in
            guard let path = track.contentUrl,
                  let url = ABSEndpoint.mediaURL(baseURL: baseURL, contentPath: path, accessToken: accessToken)
            else { return nil }
            return ResolvedTrack(url: url, offset: track.offset, duration: track.length)
        }
        load(tracks: tracks, duration: session.resolvedDuration, startingAt: bookTime)
    }

    @ObservationIgnored private var resolvedTracks: [ResolvedTrack] = []

    /// Rebuilds the queue from the track containing `bookTime`.
    ///
    /// Every remaining track is queued so transitions between files are
    /// seamless; a book should not pause between chapters because it was
    /// split into 60 MP3s.
    private func rebuildQueue(startingAtBookTime bookTime: TimeInterval) {
        guard let location = timeline.location(forBookTime: bookTime) else { return }

        player.removeAllItems()
        currentTrackIndex = location.trackIndex

        for index in location.trackIndex..<resolvedTracks.count {
            player.insert(AVPlayerItem(url: resolvedTracks[index].url), after: nil)
        }

        position = Self.playableSeconds(bookTime) ?? 0
        if location.timeInTrack > 0, let time = Self.playableTime(location.timeInTrack) {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    // MARK: - Guarding AVFoundation

    // `AVPlayer.seek` with a non-numeric `CMTime` raises an Objective-C
    // exception, which Swift cannot catch — the app is killed outright. A NaN
    // reaches here the moment any arithmetic upstream touches an indefinite
    // duration, so every seconds-to-`CMTime` conversion goes through here
    // and a bad value turns into a no-op instead of a crash.

    /// The value back, or nil when it could never be played.
    nonisolated static func playableSeconds(_ seconds: TimeInterval) -> TimeInterval? {
        seconds.isFinite ? seconds : nil
    }

    nonisolated static func playableTime(_ seconds: TimeInterval) -> CMTime? {
        guard let seconds = playableSeconds(seconds), seconds >= 0 else { return nil }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    /// Clamps into 0...limit, treating a non-finite limit as "no limit" rather
    /// than letting it poison the comparison — `max(.nan, 0)` is `.nan`.
    nonisolated static func clamp(_ value: TimeInterval, to limit: TimeInterval) -> TimeInterval {
        guard let value = playableSeconds(value) else { return 0 }
        let lower = Swift.max(value, 0)
        guard let limit = playableSeconds(limit), limit > 0 else { return lower }
        return Swift.min(lower, limit)
    }

    // MARK: - Transport

    public func play() {
        guard !timeline.isEmpty else { return }
        configureAudioSession()
        player.play()
        state = .playing
    }

    public func pause() {
        player.pause()
        state = .paused
    }

    /// Seeks in book time.
    public func seek(to bookTime: TimeInterval) {
        guard Self.playableSeconds(bookTime) != nil,
              let location = timeline.location(forBookTime: bookTime)
        else { return }

        if location.trackIndex != currentTrackIndex {
            let wasPlaying = state == .playing
            rebuildQueue(startingAtBookTime: bookTime)
            if wasPlaying { player.play() }
            return
        }

        guard let time = Self.playableTime(location.timeInTrack) else { return }
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        position = Self.clamp(bookTime, to: duration)
        onPositionChange?(position)
    }

    public func skip(by seconds: TimeInterval) {
        guard let from = Self.playableSeconds(position),
              let by = Self.playableSeconds(seconds)
        else { return }
        seek(to: Self.clamp(from + by, to: duration))
    }

    public func setRate(_ rate: PlaybackRate) {
        // Setting `rate` on a paused player starts it, which is not what a
        // speed change means.
        if state == .playing {
            player.rate = Float(rate.value)
        }
        pendingRate = rate
    }

    @ObservationIgnored private var pendingRate: PlaybackRate = .normal

    /// 0...1, used by the sleep timer's fade.
    public func setVolume(_ volume: Double) {
        player.volume = Float(min(max(volume, 0), 1))
    }

    public func stop() {
        player.pause()
        player.removeAllItems()
        state = .idle
        position = 0
        duration = 0
    }

    /// Releases the observers. Swift 6 forbids touching them from `deinit`, so
    /// the owner calls this when it is finished with the engine.
    public func tearDown() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObservation?.invalidate()
        rateObservation?.invalidate()
        stop()
    }

    // MARK: - Observation

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleTick(trackTime: time.seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleItemEnded()
            }
        }

        // These two are KVO, and KVO is delivered on whichever thread changed
        // the value. `AVPlayer` changes `rate` and `timeControlStatus` from its
        // own queues, so `MainActor.assumeIsolated` here *trapped* — the app was
        // killed the instant playback started. The periodic and notification
        // observers above are safe because they were given `queue: .main`;
        // `observe(_:options:changeHandler:)` takes no queue, so the hop has to
        // be made by hand. Read the values here, act on them on the main actor:
        // an `AVPlayer` is not `Sendable` and must not cross.
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let rate = player.rate
            Task { @MainActor [weak self] in
                guard let self else { return }
                if rate > 0, self.state != .playing { self.state = .playing }
            }
        }

        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            let rate = player.rate
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                if status == .playing {
                    // Re-apply the speed: AVPlayer resets rate to 1 whenever it
                    // resumes from a stall or a new item.
                    if abs(rate - Float(self.pendingRate.value)) > 0.001 {
                        self.player.rate = Float(self.pendingRate.value)
                    }
                }
            }
        }
    }

    private func handleTick(trackTime: TimeInterval) {
        guard trackTime.isFinite else { return }
        let bookTime = timeline.bookTime(forTrackIndex: currentTrackIndex, timeInTrack: trackTime)
        position = min(max(bookTime, 0), max(duration, 0))
        onPositionChange?(position)
    }

    private func handleItemEnded() {
        // The queue advances itself; follow it so book time stays right.
        if currentTrackIndex + 1 < resolvedTracks.count {
            currentTrackIndex += 1
            if state == .playing { player.rate = Float(pendingRate.value) }
        } else {
            state = .ended
            position = duration
            onFinished?()
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // `.spokenAudio` is what tells the system this is speech: it gets
            // the right ducking behaviour and the right CarPlay treatment.
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            failure = "Couldn't start audio."
        }
        #endif
    }
}
