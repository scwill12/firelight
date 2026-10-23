import Foundation
import Testing
@testable import ABSKit
@testable import DesignSystem
@testable import PlaybackKit

private func track(index: Int, offset: Double, duration: Double) -> ABSAudioTrack {
    let json = Data("""
    {"index":\(index),"startOffset":\(offset),"duration":\(duration),
     "title":"Track \(index)","contentUrl":"/api/items/li-1/file/\(1000 + index)",
     "mimeType":"audio/mpeg","codec":"mp3"}
    """.utf8)
    return try! ABSJSON.decoder.decode(ABSAudioTrack.self, from: json)
}

@Suite("Track timeline")
struct TrackTimelineTests {
    /// Three files: 0–600, 600–1500, 1500–2100.
    private let timeline = TrackTimeline(tracks: [
        track(index: 0, offset: 0, duration: 600),
        track(index: 1, offset: 600, duration: 900),
        track(index: 2, offset: 1500, duration: 600),
    ])

    @Test("Total duration spans every file")
    func totalDuration() {
        #expect(timeline.totalDuration == 2100)
    }

    @Test("Book time lands in the right file, at the right offset")
    func locationForBookTime() throws {
        let start = try #require(timeline.location(forBookTime: 0))
        #expect(start.trackIndex == 0)
        #expect(start.timeInTrack == 0)

        let middle = try #require(timeline.location(forBookTime: 900))
        #expect(middle.trackIndex == 1)
        #expect(middle.timeInTrack == 300)

        let late = try #require(timeline.location(forBookTime: 2000))
        #expect(late.trackIndex == 2)
        #expect(late.timeInTrack == 500)
    }

    @Test("A boundary belongs to the file that starts there")
    func boundaryBelongsToNextTrack() throws {
        let boundary = try #require(timeline.location(forBookTime: 600))
        #expect(boundary.trackIndex == 1)
        #expect(boundary.timeInTrack == 0)
    }

    @Test("Positions outside the book are clamped, never wrapped")
    func clamping() throws {
        let before = try #require(timeline.location(forBookTime: -100))
        #expect(before.trackIndex == 0)
        #expect(before.timeInTrack == 0)

        let after = try #require(timeline.location(forBookTime: 99_999))
        #expect(after.trackIndex == 2)
        #expect(after.timeInTrack == 600)
    }

    @Test("Converting back gives the book time again")
    func roundTrip() throws {
        for bookTime in [0.0, 1.0, 599.0, 600.0, 1200.0, 1500.0, 2099.0] {
            let location = try #require(timeline.location(forBookTime: bookTime))
            let roundTripped = timeline.bookTime(
                forTrackIndex: location.trackIndex,
                timeInTrack: location.timeInTrack
            )
            #expect(abs(roundTripped - bookTime) < 0.001, "round trip failed at \(bookTime)")
        }
    }

    @Test("A single-file book still works")
    func singleTrack() throws {
        let single = TrackTimeline(tracks: [track(index: 0, offset: 0, duration: 3600)])
        let location = try #require(single.location(forBookTime: 1800))
        #expect(location.trackIndex == 0)
        #expect(location.timeInTrack == 1800)
    }

    @Test("No tracks is handled, not crashed on")
    func empty() {
        let empty = TrackTimeline(tracks: [])
        #expect(empty.isEmpty)
        #expect(empty.totalDuration == 0)
        #expect(empty.location(forBookTime: 10) == nil)
    }

    @Test("Tracks delivered out of order are sorted by offset")
    func outOfOrder() throws {
        let shuffled = TrackTimeline(tracks: [
            track(index: 2, offset: 1500, duration: 600),
            track(index: 0, offset: 0, duration: 600),
            track(index: 1, offset: 600, duration: 900),
        ])
        let location = try #require(shuffled.location(forBookTime: 700))
        #expect(location.trackIndex == 1)
        #expect(location.timeInTrack == 100)
    }
}

@Suite("Chapter timeline")
struct ChapterTimelineTests {
    private let timeline = ChapterTimeline(chapters: [
        ABSChapter(id: 0, start: 0, end: 600, title: "One"),
        ABSChapter(id: 1, start: 600, end: 1500, title: "Two"),
        ABSChapter(id: 2, start: 1500, end: 2100, title: "Three"),
    ])

    @Test("Finds the chapter containing a position")
    func chapterAtTime() {
        #expect(timeline.chapter(at: 0)?.title == "One")
        #expect(timeline.chapter(at: 599)?.title == "One")
        #expect(timeline.chapter(at: 600)?.title == "Two")
        #expect(timeline.chapter(at: 2000)?.title == "Three")
    }

    @Test("Chapter progress is measured within the chapter, not the book")
    func chapterProgress() {
        #expect(abs(timeline.chapterProgress(at: 300) - 0.5) < 0.001)
        #expect(abs(timeline.chapterProgress(at: 1050) - 0.5) < 0.001)
    }

    @Test("Next chapter goes forward")
    func nextChapter() {
        #expect(timeline.startOfNextChapter(after: 100) == 600)
        #expect(timeline.startOfNextChapter(after: 1600) == nil)
    }

    @Test("Previous restarts the chapter unless you just started it")
    func previousChapter() {
        // Well into chapter two: restart chapter two.
        #expect(timeline.startOfPreviousChapter(from: 900) == 600)
        // Just inside chapter two: go back to chapter one.
        #expect(timeline.startOfPreviousChapter(from: 601) == 0)
    }

    @Test("Detects crossing a chapter boundary")
    func crossesBoundary() {
        #expect(timeline.crossesBoundary(from: 599, to: 601))
        #expect(!timeline.crossesBoundary(from: 100, to: 200))
    }

    @Test("A book with no chapters is handled everywhere")
    func noChapters() {
        let empty = ChapterTimeline(chapters: [])
        #expect(empty.isEmpty)
        #expect(empty.chapter(at: 100) == nil)
        #expect(empty.startOfNextChapter(after: 0) == nil)
        #expect(empty.chapterProgress(at: 100) == 0)
        #expect(!empty.crossesBoundary(from: 0, to: 1000))
    }
}

@Suite("Playback rate")
struct PlaybackRateTests {
    @Test("Clamped to the range the spec defines")
    func clamping() {
        #expect(PlaybackRate(0.1).value == 0.5)
        #expect(PlaybackRate(99).value == 3.5)
    }

    @Test("Snapped to 0.05 steps, with no floating-point dust")
    func snapping() {
        #expect(PlaybackRate(1.03).value == 1.05)
        #expect(PlaybackRate(1.26).value == 1.25)
        #expect(PlaybackRate(1.0).stepped(by: 1).value == 1.05)
        #expect(PlaybackRate(1.0).stepped(by: 4).value == 1.2)
    }

    @Test("Stepping stops at the ends rather than wrapping")
    func steppingBounds() {
        #expect(PlaybackRate(0.5).stepped(by: -5).value == 0.5)
        #expect(PlaybackRate(3.5).stepped(by: 5).value == 3.5)
    }

    @Test("Reads the way a person would write it")
    func description() {
        #expect(PlaybackRate(1.0).description == "1×")
        #expect(PlaybackRate(1.5).description == "1.5×")
        #expect(PlaybackRate(1.05).description == "1.05×")
        #expect(PlaybackRate(2.0).description == "2×")
    }

    @Test("Every preset is a legal value")
    func presets() {
        for preset in PlaybackRate.presets {
            #expect(PlaybackRate(preset.value) == preset)
        }
    }
}

@Suite("Smart rewind")
struct SmartRewindTests {
    private let rewind = SmartRewind.default

    @Test("A brief pause moves nothing")
    func briefPause() {
        #expect(rewind.rewind(forPauseDuration: 0) == 0)
        #expect(rewind.rewind(forPauseDuration: 5) == 0)
    }

    @Test("Longer pauses rewind further")
    func ladder() {
        #expect(rewind.rewind(forPauseDuration: 30) == 2)
        #expect(rewind.rewind(forPauseDuration: 120) == 5)
        #expect(rewind.rewind(forPauseDuration: 3600) == 10)
        #expect(rewind.rewind(forPauseDuration: 8 * 3600) == 20)
        #expect(rewind.rewind(forPauseDuration: 3 * 86_400) == 30)
    }

    @Test("Turning it off means it does nothing at all")
    func disabled() {
        var disabled = SmartRewind.default
        disabled.isEnabled = false
        #expect(disabled.rewind(forPauseDuration: 86_400) == 0)
    }
}

@Suite("Sleep timer")
struct SleepTimerTests {
    private let calculator = SleepTimerCalculator()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Off means no countdown")
    func off() {
        #expect(calculator.remaining(mode: .off, endsAt: nil, now: now, position: 0, chapterEnd: nil, rate: .normal) == nil)
    }

    @Test("A fixed timer counts down in real time")
    func duration() {
        let endsAt = now.addingTimeInterval(300)
        let remaining = calculator.remaining(
            mode: .duration(600), endsAt: endsAt, now: now,
            position: 0, chapterEnd: nil, rate: .normal
        )
        #expect(remaining == 300)
    }

    @Test("End of chapter accounts for playback speed")
    func endOfChapterWithRate() {
        // Ten minutes of chapter left, played at 2×, is five minutes of sleep.
        let remaining = calculator.remaining(
            mode: .endOfChapter, endsAt: nil, now: now,
            position: 1000, chapterEnd: 1600, rate: PlaybackRate(2.0)
        )
        #expect(remaining == 300)
    }

    @Test("The volume fades over the last 30 seconds, never before")
    func fade() {
        #expect(calculator.volumeMultiplier(remaining: 120) == 1)
        #expect(calculator.volumeMultiplier(remaining: 30) == 1)
        #expect(abs(calculator.volumeMultiplier(remaining: 15) - 0.5) < 0.001)
        #expect(calculator.volumeMultiplier(remaining: 0) == 0)
        #expect(calculator.volumeMultiplier(remaining: nil) == 1)
    }

    @Test("Expiry is reaching zero, not passing it")
    func expiry() {
        #expect(calculator.hasExpired(remaining: 0))
        #expect(!calculator.hasExpired(remaining: 1))
        #expect(!calculator.hasExpired(remaining: nil))
    }

    @Test("Shake extends a fixed timer by pushing its end back")
    func extendDuration() {
        let endsAt = now.addingTimeInterval(60)
        let extended = calculator.extended(mode: .duration(600), endsAt: endsAt, now: now)
        #expect(extended.endsAt == endsAt.addingTimeInterval(300))
    }

    @Test("Extending an end-of-chapter timer converts it to a fixed one")
    func extendEndOfChapter() {
        // "One more chapter" and "a bit longer" are different requests.
        let extended = calculator.extended(mode: .endOfChapter, endsAt: nil, now: now)
        #expect(extended.mode == .duration(300))
        #expect(extended.endsAt == now.addingTimeInterval(300))
    }
}

@Suite("Playback endpoints")
struct PlaybackEndpointTests {
    @Test("Opening a session asks for direct play")
    func playRequest() throws {
        let request = try ABSEndpoint.play(
            itemID: "li-1",
            request: PlaybackSessionRequest(deviceID: "d", clientVersion: "1.0", model: "iPhone", systemVersion: "26.0")
        )
        #expect(request.path == "/api/items/li-1/play")
        #expect(request.method == .post)

        let body = try #require(request.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["forceDirectPlay"] as? Bool == true)
        #expect((json["supportedMimeTypes"] as? [String])?.contains("audio/mpeg") == true)
    }

    @Test("A podcast episode gets its own play path")
    func episodePlayRequest() throws {
        let request = try ABSEndpoint.play(
            itemID: "li-1",
            episodeID: "ep-2",
            request: PlaybackSessionRequest(deviceID: "d", clientVersion: "1.0", model: "iPhone", systemVersion: nil)
        )
        #expect(request.path == "/api/items/li-1/play/ep-2")
    }

    @Test("Media URLs carry the token, because AVPlayer cannot send a header")
    func mediaURL() throws {
        let url = try #require(ABSEndpoint.mediaURL(
            baseURL: URL(string: "https://example.com/abs")!,
            contentPath: "/api/items/li-1/file/1001",
            accessToken: "abc123"
        ))
        #expect(url.absoluteString == "https://example.com/abs/api/items/li-1/file/1001?token=abc123")
        // The sub-path survives, and so does redaction.
        #expect(Redaction.url(url) == "https://<server>/abs/api/items/li-1/file/1001")
        #expect(!Redaction.url(url).contains("abc123"))
    }

    @Test("Deleting a bookmark puts a whole second in the path")
    func deleteBookmark() {
        let request = ABSEndpoint.deleteBookmark(itemID: "li-1", time: 1234.6)
        #expect(request.path == "/api/me/item/li-1/bookmark/1235")
        #expect(request.method == .delete)
    }
}

@Suite("Playback session decoding")
struct PlaybackSessionDecodingTests {
    @Test("Decodes a session with tracks and chapters")
    func session() throws {
        let json = Data("""
        {"id":"sess-1","userId":"usr-1","libraryItemId":"li-1","mediaType":"book",
         "displayTitle":"The Hobbit","displayAuthor":"Tolkien","duration":2100,
         "playMethod":0,"currentTime":900,"startTime":900,"timeListening":120,
         "chapters":[{"id":0,"start":0,"end":600,"title":"One"},
                     {"id":1,"start":600,"end":2100,"title":"Two"}],
         "audioTracks":[{"index":0,"startOffset":0,"duration":600,"title":"a",
                         "contentUrl":"/api/items/li-1/file/1","mimeType":"audio/mpeg","codec":"mp3"},
                        {"index":1,"startOffset":600,"duration":1500,"title":"b",
                         "contentUrl":"/api/items/li-1/file/2","mimeType":"audio/mpeg","codec":"mp3"}],
         "startedAt":1700000000000,"updatedAt":1700000100000}
        """.utf8)
        let session = try ABSJSON.decoder.decode(ABSPlaybackSession.self, from: json)

        #expect(session.id == "sess-1")
        #expect(session.orderedTracks.count == 2)
        #expect(session.orderedChapters.first?.title == "One")
        #expect(session.resolvedDuration == 2100)
        #expect(session.currentTime == 900)
    }

    @Test("A session without a duration falls back to the tracks")
    func durationFallback() throws {
        let json = Data("""
        {"id":"s","audioTracks":[{"index":0,"startOffset":0,"duration":100,"contentUrl":"/x"},
                                 {"index":1,"startOffset":100,"duration":200,"contentUrl":"/y"}]}
        """.utf8)
        let session = try ABSJSON.decoder.decode(ABSPlaybackSession.self, from: json)
        #expect(session.resolvedDuration == 300)
    }
}

@Suite("Timecode formatting")
struct TimecodeTests {
    @Test("Hours appear only when there are hours")
    func formatting() {
        #expect(PlaybackController.timecode(0) == "0:00")
        #expect(PlaybackController.timecode(59) == "0:59")
        #expect(PlaybackController.timecode(600) == "10:00")
        #expect(PlaybackController.timecode(13_330) == "3:42:10")
    }

    @Test("Nonsense in gives something sane out")
    func invalidInput() {
        #expect(PlaybackController.timecode(-5) == "0:00")
        #expect(PlaybackController.timecode(.nan) == "0:00")
        #expect(PlaybackController.timecode(.infinity) == "0:00")
    }
}

@Suite("Cover palette")
struct CoverPaletteTests {
    @Test("Every palette it produces is readable")
    func alwaysReadable() {
        let covers: [[RGBColor]] = [
            [RGBColor(r: 0.95, g: 0.93, b: 0.88)],                     // pale
            [RGBColor(r: 0.02, g: 0.02, b: 0.03)],                     // near black
            [RGBColor(r: 0.85, g: 0.15, b: 0.1)],                      // saturated red
            [RGBColor(r: 0.5, g: 0.5, b: 0.5)],                        // flat grey
            [RGBColor(r: 0.1, g: 0.4, b: 0.2), RGBColor(r: 0.9, g: 0.8, b: 0.1)],
        ]
        for pixels in covers {
            let palette = CoverPaletteExtractor.palette(fromPixels: pixels)
            #expect(
                WCAG.meetsAA(foreground: palette.primaryText, background: palette.background),
                "body text failed AA for \(pixels)"
            )
            #expect(
                WCAG.meetsAA(foreground: palette.accent, background: palette.background, largeText: true),
                "accent failed AA for \(pixels)"
            )
        }
    }

    @Test("A greyscale cover falls back to the brand accent rather than grey")
    func greyscaleFallback() {
        let palette = CoverPaletteExtractor.palette(fromPixels: [RGBColor(r: 0.4, g: 0.4, b: 0.4)])
        #expect(CoverPaletteExtractor.saturation(palette.accent) > 0.15)
    }

    @Test("No pixels means the fallback palette, not a crash")
    func noPixels() {
        #expect(CoverPaletteExtractor.palette(fromPixels: []) == .fallback)
    }

    @Test("The background is dark enough to sit a player on")
    func backgroundIsDeep() {
        let palette = CoverPaletteExtractor.palette(fromPixels: [RGBColor(r: 1, g: 1, b: 1)])
        #expect(WCAG.relativeLuminance(palette.background) < 0.2)
    }
}

@Suite("Chapter and book time")
struct TimeScopeTests {
    private let timeline = ChapterTimeline(chapters: [
        ABSChapter(id: 0, start: 0, end: 600, title: "One"),
        ABSChapter(id: 1, start: 600, end: 1500, title: "Two"),
        ABSChapter(id: 2, start: 1500, end: 2100, title: "Three"),
    ])
    private let bookDuration: TimeInterval = 2100

    private func scope(_ display: TimeDisplay, at position: TimeInterval) -> TimeScope {
        TimeScope.resolve(
            display: display,
            chapters: timeline,
            position: position,
            bookDuration: bookDuration
        )
    }

    @Test("Book time spans the whole book wherever you are in it")
    func bookScope() {
        let scope = scope(.book, at: 900)
        #expect(scope.start == 0)
        #expect(scope.duration == bookDuration)
        #expect(scope.elapsed(at: 900) == 900)
        #expect(scope.remaining(at: 900) == 1200)
    }

    @Test("Chapter time counts from the start of the chapter you are in")
    func chapterScope() {
        // 900s into the book is 300s into chapter two, which runs 600–1500.
        let scope = scope(.chapter, at: 900)
        #expect(scope.start == 600)
        #expect(scope.duration == 900)
        #expect(scope.elapsed(at: 900) == 300)
        #expect(scope.remaining(at: 900) == 600)
    }

    @Test("The scope follows you across a chapter boundary")
    func scopeMovesWithPosition() {
        #expect(scope(.chapter, at: 599).start == 0)
        #expect(scope(.chapter, at: 600).start == 600)
        #expect(scope(.chapter, at: 1500).start == 1500)
    }

    @Test("A book with no chapters falls back to book time rather than a frozen clock")
    func noChaptersFallsBack() {
        let empty = TimeScope.resolve(
            display: .chapter,
            chapters: ChapterTimeline(chapters: []),
            position: 900,
            bookDuration: bookDuration
        )
        #expect(empty.start == 0)
        #expect(empty.duration == bookDuration)
        #expect(empty.elapsed(at: 900) == 900)
    }

    @Test("A zero-length chapter falls back too")
    func zeroLengthChapterFallsBack() {
        let degenerate = TimeScope.resolve(
            display: .chapter,
            chapters: ChapterTimeline(chapters: [ABSChapter(id: 0, start: 0, end: 0, title: "Empty")]),
            position: 10,
            bookDuration: bookDuration
        )
        #expect(degenerate.duration == bookDuration)
    }

    @Test("Elapsed and remaining never go negative")
    func clampsOutsideTheScope() {
        let scope = scope(.chapter, at: 900)
        #expect(scope.elapsed(at: 0) == 0)
        #expect(scope.remaining(at: 99_999) == 0)
    }

    @Test("The fraction is measured against the scope, not the book")
    func fractionUsesTheScope() {
        #expect(scope(.chapter, at: 1050).fraction(at: 1050) == 0.5)
        #expect(scope(.book, at: 1050).fraction(at: 1050) == 0.5)
        // Same position, different meaning: halfway through chapter two is
        // only halfway through the book by coincidence here, so check one
        // that is not.
        #expect(scope(.chapter, at: 750).fraction(at: 750) != scope(.book, at: 750).fraction(at: 750))
    }

    @Test("The preference survives a round trip through the store")
    func preferenceRoundTrips() throws {
        let suite = "firelight.tests.timeDisplay.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackSettingsStore(defaults: defaults)

        #expect(store.timeDisplay == .book)
        store.timeDisplay = .chapter
        #expect(store.timeDisplay == .chapter)
        store.timeDisplay = .book
        #expect(store.timeDisplay == .book)
    }
}

@Suite("Seek guards")
struct SeekGuardTests {
    @Test("A non-finite position is never handed to AVFoundation")
    func rejectsNonFinite() {
        #expect(AudioEngine.playableSeconds(.nan) == nil)
        #expect(AudioEngine.playableSeconds(.infinity) == nil)
        #expect(AudioEngine.playableSeconds(-.infinity) == nil)
        #expect(AudioEngine.playableTime(.nan) == nil)
        #expect(AudioEngine.playableTime(.infinity) == nil)
    }

    @Test("A negative seek is refused rather than clamped silently")
    func rejectsNegativeTime() {
        #expect(AudioEngine.playableTime(-1) == nil)
        #expect(AudioEngine.playableTime(0) != nil)
    }

    @Test("Ordinary positions convert as usual")
    func convertsFiniteSeconds() throws {
        let time = try #require(AudioEngine.playableTime(90.5))
        #expect(time.seconds == 90.5)
    }

    @Test("Clamping holds a position inside the book")
    func clampsIntoRange() {
        #expect(AudioEngine.clamp(-5, to: 100) == 0)
        #expect(AudioEngine.clamp(50, to: 100) == 50)
        #expect(AudioEngine.clamp(150, to: 100) == 100)
    }

    @Test("An unknown duration does not poison the clamp")
    func indefiniteDurationIsNoLimit() {
        // `max(.nan, 0)` is `.nan`, so a live stream's indefinite duration
        // used to turn every seek into a NaN and kill the app.
        #expect(AudioEngine.clamp(50, to: .nan) == 50)
        #expect(AudioEngine.clamp(50, to: 0) == 50)
        #expect(AudioEngine.clamp(-5, to: .nan) == 0)
    }

    @Test("A non-finite position clamps to the start rather than propagating")
    func nonFiniteValueClampsToZero() {
        #expect(AudioEngine.clamp(.nan, to: 100) == 0)
        #expect(AudioEngine.clamp(.infinity, to: .nan) == 0)
    }
}

@Suite("Lock screen preference")
struct LiveActivityPreferenceTests {
    @Test("Off by default, so the lock screen shows one control not two")
    func defaultsToOff() throws {
        let suite = "firelight.tests.liveActivity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PlaybackSettingsStore(defaults: defaults).liveActivityPreference == .off)
        #expect(!LiveActivityPreference.default.isOn)
    }

    @Test("The choice survives a round trip")
    func roundTrips() throws {
        let suite = "firelight.tests.liveActivity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackSettingsStore(defaults: defaults)

        store.liveActivityPreference = .on
        #expect(store.liveActivityPreference == .on)
        #expect(store.liveActivityPreference.isOn)
        store.liveActivityPreference = .off
        #expect(store.liveActivityPreference == .off)
    }

    @Test("An unrecognised stored value falls back rather than throwing")
    func unknownValueFallsBack() throws {
        let suite = "firelight.tests.liveActivity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("sometimes", forKey: "firelight.liveActivity")
        #expect(PlaybackSettingsStore(defaults: defaults).liveActivityPreference == .off)
    }
}

@Suite("Silent launch")
struct SilentLaunchTests {
    /// The flag exists so an automated run cannot make noise on someone's
    /// machine. In the unit tests the app is launched without it, so the
    /// guard must be inert — a test suite that silently disabled audio would
    /// hide a real regression.
    @Test("Audio is not silenced unless the flag was passed")
    func offByDefault() {
        #expect(!ProcessInfo.processInfo.arguments.contains("-FirelightSilent"))
        #expect(!AudioEngine.isSilenced)
    }
}
