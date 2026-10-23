import Foundation

/// What the player is doing, as the UI, the widgets and the watch app see it.
public enum PlaybackState: String, Sendable, Hashable, Codable {
    case idle
    case loading
    case playing
    case paused
    /// Reached the end of the item.
    case ended
    case failed
}

/// The player seam. Phase 3 implements it on AVFoundation; the widgets and the
/// watch app only ever see this protocol, so neither links the audio engine.
public protocol AudioPlayerControlling: Sendable {
    var state: PlaybackState { get async }
    func play() async
    func pause() async
    func seek(to seconds: TimeInterval) async
    func skip(by seconds: TimeInterval) async
}

public enum PlaybackError: Error, Sendable, Equatable {
    case noPlayableTrack
    case sessionOpenFailed
    case assetUnavailableOffline
}
