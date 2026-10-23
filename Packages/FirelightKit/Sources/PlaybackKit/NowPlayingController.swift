import ABSKit
import Foundation
import MediaPlayer

/// The lock screen, Control Center, CarPlay and the AirPods stem.
///
/// All of them read `MPNowPlayingInfoCenter` and send `MPRemoteCommandCenter`
/// commands, so wiring them once here is what makes every one of them work.
@MainActor
public final class NowPlayingController {
    public struct Handlers {
        public var play: @MainActor () -> Void
        public var pause: @MainActor () -> Void
        public var skipForward: @MainActor () -> Void
        public var skipBackward: @MainActor () -> Void
        public var nextChapter: @MainActor () -> Void
        public var previousChapter: @MainActor () -> Void
        public var seek: @MainActor (TimeInterval) -> Void

        public init(
            play: @escaping @MainActor () -> Void,
            pause: @escaping @MainActor () -> Void,
            skipForward: @escaping @MainActor () -> Void,
            skipBackward: @escaping @MainActor () -> Void,
            nextChapter: @escaping @MainActor () -> Void,
            previousChapter: @escaping @MainActor () -> Void,
            seek: @escaping @MainActor (TimeInterval) -> Void
        ) {
            self.play = play
            self.pause = pause
            self.skipForward = skipForward
            self.skipBackward = skipBackward
            self.nextChapter = nextChapter
            self.previousChapter = previousChapter
            self.seek = seek
        }
    }

    private var isWired = false

    public init() {}

    public func wire(_ handlers: Handlers, skipInterval: SkipInterval) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)

        center.playCommand.addTarget { _ in handlers.play(); return .success }
        center.pauseCommand.addTarget { _ in handlers.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in
            // The system does not tell us which it meant; the caller knows.
            handlers.play()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval.forward)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval.backward)]
        center.skipForwardCommand.addTarget { _ in handlers.skipForward(); return .success }
        center.skipBackwardCommand.addTarget { _ in handlers.skipBackward(); return .success }

        // Track buttons mean chapters in an audiobook, not files.
        center.nextTrackCommand.addTarget { _ in handlers.nextChapter(); return .success }
        center.previousTrackCommand.addTarget { _ in handlers.previousChapter(); return .success }

        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            handlers.seek(event.positionTime)
            return .success
        }

        isWired = true
    }

    /// Updates what the lock screen shows.
    ///
    /// The title is the *chapter* when there is one, with the book as the
    /// album — that is what makes a 40-hour book navigable from a car stereo.
    public func update(
        bookTitle: String,
        author: String?,
        chapterTitle: String?,
        position: TimeInterval,
        duration: TimeInterval,
        rate: PlaybackRate,
        isPlaying: Bool,
        artwork: MPMediaItemArtwork?
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle ?? bookTitle,
            MPMediaItemPropertyAlbumTitle: bookTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate.value : 0,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let author { info[MPMediaItemPropertyArtist] = author }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #if os(iOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
    }

    public func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if os(iOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        #endif
    }
}
