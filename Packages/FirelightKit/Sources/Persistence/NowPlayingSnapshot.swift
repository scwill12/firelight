import Foundation

/// What the app is playing, in a form the widgets and the Live Activity can
/// read without opening the database.
///
/// A widget gets a few milliseconds and runs in its own process; asking it to
/// stand up a SwiftData container to draw one line of text is how widgets end
/// up blank. The app writes this on every meaningful change and the extensions
/// only read it.
public struct NowPlayingSnapshot: Sendable, Hashable, Codable {
    public var itemID: String
    public var title: String
    public var author: String?
    public var chapterTitle: String?
    /// Seconds into the book.
    public var position: TimeInterval
    public var duration: TimeInterval
    public var isPlaying: Bool
    /// When this snapshot was written, so a widget can tell stale from paused.
    public var updatedAt: Date

    public init(
        itemID: String,
        title: String,
        author: String? = nil,
        chapterTitle: String? = nil,
        position: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool,
        updatedAt: Date = .now
    ) {
        self.itemID = itemID
        self.title = title
        self.author = author
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

    /// A paused snapshot is accurate indefinitely; a playing one drifts, so
    /// the widget advances it by however long ago it was written.
    public func projected(to now: Date = .now) -> NowPlayingSnapshot {
        guard isPlaying else { return self }
        var copy = self
        copy.position = min(duration, position + max(0, now.timeIntervalSince(updatedAt)))
        copy.updatedAt = now
        return copy
    }
}

public extension SharedState {
    private static var nowPlayingKey: String { "firelight.shared.nowPlaying" }

    /// The current snapshot, or nil when nothing is loaded.
    static var nowPlaying: NowPlayingSnapshot? {
        get {
            guard let data = AppGroup.defaults?.data(forKey: nowPlayingKey) else { return nil }
            return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                AppGroup.defaults?.removeObject(forKey: nowPlayingKey)
                return
            }
            AppGroup.defaults?.set(data, forKey: nowPlayingKey)
        }
    }

    private static var activeServerKey: String { "firelight.shared.activeServer" }

    /// Enough for an extension to build a client: the id keys the Keychain,
    /// the URL is where to send it. Written whenever the app connects.
    static var activeServer: (id: UUID, baseURL: URL)? {
        get {
            guard let stored = AppGroup.defaults?.dictionary(forKey: activeServerKey),
                  let idString = stored["id"] as? String, let id = UUID(uuidString: idString),
                  let urlString = stored["url"] as? String, let url = URL(string: urlString)
            else { return nil }
            return (id, url)
        }
        set {
            guard let newValue else {
                AppGroup.defaults?.removeObject(forKey: activeServerKey)
                return
            }
            AppGroup.defaults?.set(
                ["id": newValue.id.uuidString, "url": newValue.baseURL.absoluteString],
                forKey: activeServerKey
            )
        }
    }

    private static var kidsModeKey: String { "firelight.shared.kidsMode" }

    /// Kids mode is in the shared container so the extensions respect it too.
    static var isKidsModeEnabled: Bool {
        get { AppGroup.defaults?.bool(forKey: kidsModeKey) ?? false }
        set { AppGroup.defaults?.set(newValue, forKey: kidsModeKey) }
    }

    private static var streakKey: String { "firelight.shared.streak" }

    /// Days in a row with some listening, for the streak widget.
    static var listeningStreak: Int {
        get { AppGroup.defaults?.integer(forKey: streakKey) ?? 0 }
        set { AppGroup.defaults?.set(newValue, forKey: streakKey) }
    }
}

/// Counts consecutive days with listening in them.
///
/// Pure, because "does today still count at 00:30?" is a question about
/// calendars and time zones, not about the database — and it is exactly the
/// sort of thing that is wrong for one user in one zone forever.
public struct ListeningStreak: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Days in a row ending today or yesterday.
    ///
    /// Yesterday still counts: someone who listens every evening should not
    /// lose their streak every morning before they have had a chance to.
    public func currentStreak(from dates: [Date], now: Date = .now) -> Int {
        guard !dates.isEmpty else { return 0 }

        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// The longest run in the history, for the stats screen in Phase 17.
    public func longestStreak(from dates: [Date]) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var current = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap == 1 {
                current += 1
                longest = max(longest, current)
            } else if gap > 1 {
                current = 1
            }
        }
        return longest
    }
}
