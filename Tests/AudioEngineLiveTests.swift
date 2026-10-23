import ABSKit
import AVFoundation
import Foundation
import Testing
@testable import PlaybackKit

/// Drives a real `AVPlayer`, because the bugs that kill playback do not live
/// in the arithmetic — they live in what AVFoundation calls back, on which
/// thread, and when.
@MainActor
@Suite("Audio engine against a real player", .serialized)
struct AudioEngineLiveTests {
    /// Writes a short silent file. A real file is the point: `AVPlayer` only
    /// emits the `rate` and `timeControlStatus` changes that matter here once
    /// it has something it can actually decode.
    private func makeSilentFile(seconds: Double) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "firelight-\(UUID().uuidString).caf")
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        )
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    @Test("Starting playback does not trap")
    func playDoesNotTrap() async throws {
        let url = try makeSilentFile(seconds: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = AudioEngine()
        engine.load(
            tracks: [AudioEngine.ResolvedTrack(url: url, offset: 0, duration: 3)],
            duration: 3,
            startingAt: 0
        )
        engine.play()
        // Long enough for the rate and timeControlStatus observers to fire,
        // which is where the app was being killed.
        try await Task.sleep(for: .seconds(2))

        #expect(engine.failure == nil)
        engine.tearDown()
    }

    @Test("Seeking across a track boundary does not trap")
    func seekAcrossTracksDoesNotTrap() async throws {
        let first = try makeSilentFile(seconds: 2)
        let second = try makeSilentFile(seconds: 2)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let engine = AudioEngine()
        engine.load(
            tracks: [
                AudioEngine.ResolvedTrack(url: first, offset: 0, duration: 2),
                AudioEngine.ResolvedTrack(url: second, offset: 2, duration: 2),
            ],
            duration: 4,
            startingAt: 0
        )
        engine.play()
        try await Task.sleep(for: .milliseconds(500))
        engine.seek(to: 3)
        try await Task.sleep(for: .seconds(1))

        #expect(engine.failure == nil)
        engine.tearDown()
    }

    @Test("A book that plays to the end does not trap")
    func playingToTheEndDoesNotTrap() async throws {
        let url = try makeSilentFile(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = AudioEngine()
        engine.load(
            tracks: [AudioEngine.ResolvedTrack(url: url, offset: 0, duration: 1)],
            duration: 1,
            startingAt: 0
        )
        engine.play()
        try await Task.sleep(for: .seconds(2))
        engine.tearDown()
    }
}

/// Drives the whole controller, not just the engine: opening a session wires
/// the remote commands, the Now Playing centre and the Live Activity, and
/// those run only on a real device-shaped stack.
@MainActor
@Suite("Playback controller against a real player", .serialized)
struct PlaybackControllerLiveTests {
    private func makeSilentFile(seconds: Double) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "firelight-\(UUID().uuidString).caf")
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        )
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    private func controller(suite: String) -> PlaybackController {
        PlaybackController(
            settings: PlaybackSettingsStore(defaults: UserDefaults(suiteName: suite) ?? .standard),
            client: { nil },
            baseURL: { nil },
            accessToken: { nil }
        )
    }

    @Test("Opening a downloaded book and playing it does not trap")
    func openAndPlayDoesNotTrap() async throws {
        let url = try makeSilentFile(seconds: 4)
        defer { try? FileManager.default.removeItem(at: url) }

        let suite = "firelight.tests.player.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let player = controller(suite: suite)
        player.localTracksProvider = { _, _ in
            [AudioEngine.ResolvedTrack(url: url, offset: 0, duration: 4)]
        }

        await player.open(itemID: "item-1", title: "A Silent Book", author: "Nobody")
        // Through the ticking, the Now Playing update and the Live Activity.
        try await Task.sleep(for: .seconds(2))

        #expect(player.isPlaying)
        #expect(player.failure == nil)

        player.pause()
        player.skipForward()
        player.skipBackward()
        player.seek(to: 1)
        try await Task.sleep(for: .milliseconds(500))
        #expect(player.failure == nil)
    }

    @Test("A book with no chapters still plays")
    func noChaptersStillPlays() async throws {
        let url = try makeSilentFile(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let suite = "firelight.tests.player.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let player = controller(suite: suite)
        player.localTracksProvider = { _, _ in
            [AudioEngine.ResolvedTrack(url: url, offset: 0, duration: 2)]
        }

        await player.open(itemID: "item-2", title: "No Chapters", author: nil)
        try await Task.sleep(for: .seconds(1))

        #expect(player.chapters.isEmpty)
        #expect(player.timeScope.duration > 0)
        #expect(player.failure == nil)
    }
}
