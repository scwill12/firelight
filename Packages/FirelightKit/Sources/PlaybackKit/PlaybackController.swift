import ABSKit
import DesignSystem
import Foundation
import MediaPlayer
import Observation
import Persistence
import SyncEngine
#if canImport(UIKit)
import UIKit
#endif

/// What the player UI talks to.
///
/// Owns the session with the server, the engine, the sleep timer and the
/// progress reporting. Nothing else opens a session or writes a position.
@MainActor
@Observable
public final class PlaybackController: PlaybackIntentHandling {
    // What is playing
    public private(set) var itemID: String?
    /// Set when what is playing is a podcast episode rather than a book.
    public private(set) var episodeID: String?
    public private(set) var title: String = ""
    public private(set) var author: String?
    public private(set) var chapters = ChapterTimeline(chapters: [])
    public private(set) var bookmarks: [ABSBookmark] = []

    // Where we are
    public var position: TimeInterval { engine.position }
    public var duration: TimeInterval { engine.duration }
    public var state: PlaybackState { engine.state }
    public var isBuffering: Bool { engine.isBuffering }
    public var failure: String? { engine.failure ?? sessionFailure }

    // Settings
    public private(set) var rate: PlaybackRate = .normal
    public var skipInterval: SkipInterval = .default
    public var smartRewind: SmartRewind = .default
    /// Whether the clock reads against the chapter or the book.
    public private(set) var timeDisplay: TimeDisplay = .default

    // Sleep timer
    public private(set) var sleepMode: SleepTimerMode = .off
    public private(set) var sleepRemaining: TimeInterval?

    public let engine = AudioEngine()

    @ObservationIgnored private let nowPlaying = NowPlayingController()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private let sleepCalculator = SleepTimerCalculator()
    @ObservationIgnored private let settings: PlaybackSettingsStore
    @ObservationIgnored private var clientProvider: @MainActor () -> ABSClient?
    @ObservationIgnored private var baseURLProvider: @MainActor () -> URL?
    @ObservationIgnored private var tokenProvider: @MainActor () async -> String?

    @ObservationIgnored private var session: ABSPlaybackSession?
    @ObservationIgnored private var sessionFailure: String?
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var sleepEndsAt: Date?
    @ObservationIgnored private var lastSyncedAt: Date?
    @ObservationIgnored private var lastSyncedPosition: TimeInterval = 0
    @ObservationIgnored private var listenedSinceSync: TimeInterval = 0
    @ObservationIgnored private var lastChapterIndex: Int?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    /// How often an open session reports in while playing.
    private let syncInterval: TimeInterval = 15

    /// Called before every network sync so the journal is written first.
    /// Phase 4 wires this to `ProgressSyncService`; without it, positions live
    /// only as long as the connection does.
    public var onRecordPosition: (@MainActor (_ itemID: String, _ episodeID: String?, _ currentTime: TimeInterval, _ duration: TimeInterval, _ listened: TimeInterval) -> Void)?
    /// Called when a session opens, so the journal can group an offline listen.
    public var onSessionBegan: (@MainActor () -> Void)?
    public var onSessionEnded: (@MainActor () -> Void)?
    /// Supplies local files for a downloaded item. When it returns tracks,
    /// they are used instead of streaming — which is also what makes playback
    /// work with no connection at all.
    public var localTracksProvider: (@MainActor (_ itemID: String, _ episodeID: String?) async -> [AudioEngine.ResolvedTrack])?
    /// The position to start from when there is no server to ask.
    public var offlinePositionProvider: (@MainActor (_ itemID: String) async -> TimeInterval?)?
    /// True when the current item is playing from disk.
    public private(set) var isPlayingOffline = false

    public init(
        settings: PlaybackSettingsStore = PlaybackSettingsStore(),
        client: @escaping @MainActor () -> ABSClient?,
        baseURL: @escaping @MainActor () -> URL?,
        accessToken: @escaping @MainActor () async -> String?
    ) {
        self.settings = settings
        self.clientProvider = client
        self.baseURLProvider = baseURL
        self.tokenProvider = accessToken
        self.skipInterval = settings.skipInterval
        self.smartRewind = settings.smartRewind
        self.timeDisplay = settings.timeDisplay

        engine.onPositionChange = { [weak self] position in
            self?.handlePositionChange(position)
        }
        engine.onFinished = { [weak self] in
            Task { await self?.handleFinished() }
        }
    }

    public var isPlaying: Bool { state == .playing }

    public var currentChapter: ABSChapter? { chapters.chapter(at: position) }

    /// Progress through the whole book, 0...1.
    public var bookProgress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    public var chapterProgress: Double { chapters.chapterProgress(at: position) }

    public var timeRemainingInBook: TimeInterval { max(0, duration - position) }

    public var timeRemainingInChapter: TimeInterval {
        guard let chapter = currentChapter else { return timeRemainingInBook }
        return max(0, chapter.end - position)
    }

    // MARK: - Opening

    /// Opens a session and starts playing.
    public func open(
        itemID: String,
        episodeID: String? = nil,
        title: String,
        author: String?,
        startPlaying: Bool = true
    ) async {
        await closeCurrentSession()

        self.itemID = itemID
        self.episodeID = episodeID
        self.title = title
        self.author = author
        self.rate = settings.rate(forItemID: itemID)
        sessionFailure = nil
        lastChapterIndex = nil

        let localTracks = await localTracksProvider?(itemID, episodeID) ?? []
        isPlayingOffline = !localTracks.isEmpty

        // Try the server for chapters and the authoritative position. A
        // downloaded book plays without it, which is the whole point.
        var session: ABSPlaybackSession?
        if let client = clientProvider() {
            let request = PlaybackSessionRequest(
                deviceID: DeviceIdentity.cached().id,
                clientVersion: Bundle.main.shortVersion,
                model: Self.deviceModel,
                systemVersion: Self.systemVersion
            )
            session = try? await client.openPlaybackSession(
                itemID: itemID, episodeID: episodeID, request: request
            )
        }

        guard session != nil || !localTracks.isEmpty else {
            sessionFailure = "Not connected, and this book isn't downloaded."
            return
        }

        self.session = session
        chapters = ChapterTimeline(chapters: session?.orderedChapters ?? [])

        let offlinePosition = await offlinePositionProvider?(itemID)
        let knownPosition = session?.currentTime ?? offlinePosition ?? 0
        let rewind = smartRewind.rewind(forPauseDuration: pauseDuration(since: session?.updatedAt))
        let start = max(0, knownPosition - rewind)

        if !localTracks.isEmpty {
            let duration = session?.resolvedDuration ?? localTracks.reduce(0) { max($0, $1.offset + $1.duration) }
            engine.load(tracks: localTracks, duration: duration, startingAt: start)
        } else if let session, let baseURL = baseURLProvider() {
            engine.load(
                session: session,
                baseURL: baseURL,
                accessToken: await tokenProvider(),
                startingAt: start
            )
        }

        engine.setRate(rate)
        lastSyncedPosition = start
        listenedSinceSync = 0

        wireRemoteCommands()
        onSessionBegan?()
        if startPlaying { play() }
        await loadBookmarks()
    }

    /// How long since the last listen, for smart rewind.
    private func pauseDuration(since lastUpdate: Date?) -> TimeInterval {
        if let pausedAt { return Date.now.timeIntervalSince(pausedAt) }
        guard let lastUpdate else { return 0 }
        return max(0, Date.now.timeIntervalSince(lastUpdate))
    }

    // MARK: - Transport

    public func play() {
        if let pausedAt {
            let rewind = smartRewind.rewind(forPauseDuration: Date.now.timeIntervalSince(pausedAt))
            if rewind > 0 { engine.seek(to: max(0, position - rewind)) }
            self.pausedAt = nil
        }
        engine.play()
        engine.setRate(rate)
        startTicking()
        updateNowPlaying()
    }

    public func pause() {
        engine.pause()
        pausedAt = .now
        stopTicking()
        updateNowPlaying()
        Task { await syncProgress(force: true) }
    }

    public func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    public func seek(to time: TimeInterval) {
        engine.seek(to: time)
        updateNowPlaying()
    }

    public func skipForward() {
        engine.skip(by: skipInterval.forward)
        updateNowPlaying()
    }

    public func skipBackward() {
        engine.skip(by: -skipInterval.backward)
        updateNowPlaying()
    }

    public func nextChapter() {
        guard let next = chapters.startOfNextChapter(after: position) else { return }
        seek(to: next)
        Haptics.impact(.chapterMark)
    }

    public func previousChapter() {
        guard let previous = chapters.startOfPreviousChapter(from: position) else { return }
        seek(to: previous)
        Haptics.impact(.chapterMark)
    }

    public func setRate(_ newRate: PlaybackRate) {
        rate = newRate
        engine.setRate(newRate)
        if let itemID { settings.setRate(newRate, forItemID: itemID) }
        updateNowPlaying()
    }

    public func setTimeDisplay(_ display: TimeDisplay) {
        timeDisplay = display
        settings.timeDisplay = display
        updateNowPlaying()
    }

    /// Flips between the two, for the tap on the clock itself.
    public func toggleTimeDisplay() {
        setTimeDisplay(timeDisplay == .book ? .chapter : .book)
    }

    public func setSkipInterval(_ interval: SkipInterval) {
        skipInterval = interval
        settings.skipInterval = interval
        wireRemoteCommands()
    }

    // MARK: - Sleep timer

    public func setSleepTimer(_ mode: SleepTimerMode) {
        sleepMode = mode
        switch mode {
        case .off:
            sleepEndsAt = nil
            sleepRemaining = nil
            engine.setVolume(1)
        case .duration(let length):
            sleepEndsAt = Date.now.addingTimeInterval(length)
        case .endOfChapter:
            sleepEndsAt = nil
        }
        updateSleepTimer()
    }

    /// Shake to extend — the one gesture you can do half asleep.
    public func extendSleepTimer() {
        let extended = sleepCalculator.extended(mode: sleepMode, endsAt: sleepEndsAt, now: .now)
        sleepMode = extended.mode
        sleepEndsAt = extended.endsAt
        engine.setVolume(1)
        updateSleepTimer()
        Haptics.selection()
    }

    private func updateSleepTimer() {
        sleepRemaining = sleepCalculator.remaining(
            mode: sleepMode,
            endsAt: sleepEndsAt,
            now: .now,
            position: position,
            chapterEnd: chapters.endOfChapter(at: position),
            rate: rate
        )
        engine.setVolume(sleepCalculator.volumeMultiplier(remaining: sleepRemaining))

        if sleepCalculator.hasExpired(remaining: sleepRemaining), isPlaying {
            pause()
            setSleepTimer(.off)
            engine.setVolume(1)
            Haptics.timerEnded()
        }
    }

    // MARK: - Chapter-relative time

    /// Where the clock starts counting from, and how long it runs for, under
    /// the current `timeDisplay`. The book when there are no chapters, since
    /// a chapter clock with no chapters would read zero forever.
    public var timeScope: TimeScope {
        TimeScope.resolve(
            display: timeDisplay,
            chapters: chapters,
            position: position,
            bookDuration: duration
        )
    }

    /// Elapsed time under the current scope.
    public var scopedElapsed: TimeInterval { timeScope.elapsed(at: position) }

    /// Remaining time under the current scope.
    public var scopedRemaining: TimeInterval { timeScope.remaining(at: position) }

    // MARK: - Bookmarks

    public func loadBookmarks() async {
        guard let client = clientProvider(), let itemID else { return }
        bookmarks = (try? await client.bookmarks(itemID: itemID)) ?? []
    }

    @discardableResult
    public func addBookmark(title: String?) async -> Bool {
        guard let client = clientProvider(), let itemID else { return false }
        let label = title?.isEmpty == false
            ? title!
            : (currentChapter?.title ?? Self.timecode(position))
        do {
            let bookmark = try await client.createBookmark(itemID: itemID, time: position, title: label)
            bookmarks.append(bookmark)
            Haptics.success()
            return true
        } catch {
            return false
        }
    }

    public func deleteBookmark(_ bookmark: ABSBookmark) async {
        guard let client = clientProvider(), let itemID else { return }
        try? await client.deleteBookmark(itemID: itemID, time: bookmark.time)
        bookmarks.removeAll { $0.time == bookmark.time }
    }

    // MARK: - Progress

    private func handlePositionChange(_ position: TimeInterval) {
        // A chapter change is worth a haptic and a sync.
        if let index = chapters.index(at: position), index != lastChapterIndex {
            if lastChapterIndex != nil {
                Haptics.impact(.chapterMark)
                Task { await syncProgress(force: true) }
            }
            lastChapterIndex = index
            updateNowPlaying()
        }
        updateSleepTimer()
    }

    /// Reports into the open session. Phase 4 replaces this with the journal,
    /// which survives being offline; this writes straight through.
    public func syncProgress(force: Bool = false) async {
        guard let client = clientProvider(), let session else { return }
        let now = Date.now
        if !force, let lastSyncedAt, now.timeIntervalSince(lastSyncedAt) < syncInterval { return }

        let listened = max(0, position - lastSyncedPosition)
        lastSyncedAt = now
        lastSyncedPosition = position
        listenedSinceSync = 0

        // Local first, always: if the network call below never happens, the
        // position still survives.
        if let itemID {
            onRecordPosition?(itemID, episodeID, position, duration, listened)
        }

        try? await client.syncSession(
            id: session.id,
            currentTime: position,
            timeListened: listened,
            duration: duration
        )
    }

    private func handleFinished() async {
        await syncProgress(force: true)
        await closeCurrentSession()
        nowPlaying.clear()
    }

    /// Moves the player to a position that came from elsewhere — the server,
    /// the socket, or the user choosing one in the conflict prompt.
    public func applyRemotePosition(_ position: ProgressPosition) {
        guard position.itemID == itemID, let currentTime = position.currentTime else { return }
        engine.seek(to: currentTime)
        lastSyncedPosition = currentTime
        updateNowPlaying()
    }

    public func closeCurrentSession() async {
        onSessionEnded?()
        liveActivity.end()
        SharedState.nowPlaying = nil
        WidgetRefresher.reload()
        guard let client = clientProvider(), let session else { return }
        try? await client.closeSession(
            id: session.id,
            currentTime: position,
            timeListened: max(0, position - lastSyncedPosition),
            duration: duration
        )
        self.session = nil
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isPlaying else { continue }
                self.updateSleepTimer()
                await self.syncProgress()
                self.updateNowPlaying()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Now Playing

    private func wireRemoteCommands() {
        nowPlaying.wire(
            NowPlayingController.Handlers(
                play: { [weak self] in self?.togglePlayPause() },
                pause: { [weak self] in self?.pause() },
                skipForward: { [weak self] in self?.skipForward() },
                skipBackward: { [weak self] in self?.skipBackward() },
                nextChapter: { [weak self] in self?.nextChapter() },
                previousChapter: { [weak self] in self?.previousChapter() },
                seek: { [weak self] time in self?.seek(to: time) }
            ),
            skipInterval: skipInterval
        )
    }

    public var artwork: MPMediaItemArtwork?

    private func updateNowPlaying() {
        guard let itemID else { return }
        nowPlaying.update(
            bookTitle: title,
            author: author,
            chapterTitle: currentChapter?.title,
            position: position,
            duration: duration,
            rate: rate,
            isPlaying: isPlaying,
            artwork: artwork
        )
        publishSnapshot(itemID: itemID)
    }

    /// Keeps the widgets and the Live Activity in step with the player.
    ///
    /// Written on every meaningful change rather than on a timer: a widget
    /// reads this in its own process and has no way to ask the app anything.
    private func publishSnapshot(itemID: String) {
        SharedState.nowPlaying = NowPlayingSnapshot(
            itemID: itemID,
            title: title,
            author: author,
            chapterTitle: currentChapter?.title,
            position: position,
            duration: duration,
            isPlaying: isPlaying
        )
        WidgetRefresher.reload()

        #if canImport(ActivityKit) && os(iOS)
        let state = PlaybackActivityAttributes.ContentState(
            chapterTitle: currentChapter?.title,
            position: position,
            duration: duration,
            isPlaying: isPlaying
        )
        if isPlaying || liveActivity.isRunning {
            liveActivity.start(itemID: itemID, title: title, author: author, state: state)
        }
        #endif
    }

    // MARK: - Helpers

    /// "3:42:10" or "42:10". Pure, so it is usable from any context.
    public nonisolated static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private static var deviceModel: String {
        #if os(watchOS)
        "Apple Watch"
        #elseif canImport(UIKit)
        UIDevice.current.model
        #else
        "Mac"
        #endif
    }

    private static var systemVersion: String? {
        #if canImport(UIKit)
        UIDevice.current.systemVersion
        #else
        nil
        #endif
    }
}

/// Per-book speed and the global transport preferences.
///
/// `@unchecked` because `UserDefaults` is documented as thread-safe but is not
/// marked `Sendable`; this type adds no mutable state of its own.
public struct PlaybackSettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func rate(forItemID itemID: String) -> PlaybackRate {
        let stored = defaults.double(forKey: "firelight.rate.\(itemID)")
        return stored > 0 ? PlaybackRate(stored) : PlaybackRate(defaults.double(forKey: "firelight.rate.default").nonZero ?? 1)
    }

    public func setRate(_ rate: PlaybackRate, forItemID itemID: String) {
        defaults.set(rate.value, forKey: "firelight.rate.\(itemID)")
        defaults.set(rate.value, forKey: "firelight.rate.default")
    }

    public var skipInterval: SkipInterval {
        get {
            let back = defaults.double(forKey: "firelight.skip.backward").nonZero ?? 15
            let forward = defaults.double(forKey: "firelight.skip.forward").nonZero ?? 30
            return SkipInterval(backward: back, forward: forward)
        }
        nonmutating set {
            defaults.set(newValue.backward, forKey: "firelight.skip.backward")
            defaults.set(newValue.forward, forKey: "firelight.skip.forward")
        }
    }

    public var timeDisplay: TimeDisplay {
        get {
            guard let raw = defaults.string(forKey: "firelight.timeDisplay") else { return .default }
            return TimeDisplay(rawValue: raw) ?? .default
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: "firelight.timeDisplay")
        }
    }

    public var smartRewind: SmartRewind {
        get {
            guard defaults.object(forKey: "firelight.smartRewind.enabled") != nil else { return .default }
            var rewind = SmartRewind.default
            rewind.isEnabled = defaults.bool(forKey: "firelight.smartRewind.enabled")
            return rewind
        }
        nonmutating set {
            defaults.set(newValue.isEnabled, forKey: "firelight.smartRewind.enabled")
        }
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
