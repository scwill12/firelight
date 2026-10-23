import AppIntents
import Foundation

/// What an App Intent needs the player to do.
///
/// `PlaybackController` conforms; the protocol exists so the intents do not
/// drag the whole player into the widget extension's address space.
@MainActor
public protocol PlaybackIntentHandling: AnyObject {
    var isPlaying: Bool { get }
    func play()
    func pause()
    func togglePlayPause()
    func skipForward()
    func skipBackward()
    func setSleepTimer(_ mode: SleepTimerMode)
    func addBookmark(title: String?) async -> Bool
}

/// How an intent finds the running player.
///
/// The project rule is "inject everything, no singletons", and this is the one
/// place it cannot hold: App Intents are instantiated by the system with no
/// context to inject into. The app registers itself here on launch, and an
/// intent that arrives when nothing is registered reports that plainly rather
/// than pretending to have worked.
@MainActor
public enum PlaybackIntentBridge {
    public private(set) static weak var handler: (any PlaybackIntentHandling)?

    public static func register(_ handler: any PlaybackIntentHandling) {
        self.handler = handler
    }

    static func require() throws -> any PlaybackIntentHandling {
        guard let handler else { throw PlaybackIntentError.nothingPlaying }
        return handler
    }
}

public enum PlaybackIntentError: Error, CustomLocalizedStringResourceConvertible {
    case nothingPlaying
    case bookmarkFailed

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingPlaying: "Firelight isn't playing anything."
        case .bookmarkFailed: "Firelight couldn't save a bookmark."
        }
    }
}

/// `AudioPlaybackIntent` is what tells the system this controls audio, which
/// is what lets it run in the app's own process rather than launching it.
public struct TogglePlaybackIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Play or Pause"
    public static let description = IntentDescription("Plays or pauses the current book.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try PlaybackIntentBridge.require().togglePlayPause()
        return .result()
    }
}

public struct ResumePlaybackIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Resume"
    public static let description = IntentDescription("Resumes the current book.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try PlaybackIntentBridge.require().play()
        return .result()
    }
}

public struct PausePlaybackIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Pause"
    public static let description = IntentDescription("Pauses the current book.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try PlaybackIntentBridge.require().pause()
        return .result()
    }
}

public struct SkipForwardIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Skip Forward"
    public static let description = IntentDescription("Skips forward by your chosen interval.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try PlaybackIntentBridge.require().skipForward()
        return .result()
    }
}

public struct SkipBackIntent: AudioPlaybackIntent {
    public static let title: LocalizedStringResource = "Skip Back"
    public static let description = IntentDescription("Skips back by your chosen interval.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        try PlaybackIntentBridge.require().skipBackward()
        return .result()
    }
}

public struct SetSleepTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Sleep Timer"
    public static let description = IntentDescription("Stops playback after a while, or at the end of the chapter.")

    @Parameter(title: "Minutes", description: "Leave empty to stop at the end of the chapter.")
    public var minutes: Int?

    public init() {}

    public init(minutes: Int?) {
        self.minutes = minutes
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        let handler = try PlaybackIntentBridge.require()
        if let minutes, minutes > 0 {
            handler.setSleepTimer(.duration(TimeInterval(minutes) * 60))
        } else {
            handler.setSleepTimer(.endOfChapter)
        }
        return .result()
    }
}

public struct AddBookmarkIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Bookmark"
    public static let description = IntentDescription("Saves the current spot.")

    @Parameter(title: "Note")
    public var note: String?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        let saved = await (try PlaybackIntentBridge.require()).addBookmark(title: note)
        guard saved else { throw PlaybackIntentError.bookmarkFailed }
        return .result()
    }
}

/// What Siri and Shortcuts offer without the user wiring anything up.
public struct FirelightShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResumePlaybackIntent(),
            phrases: ["Resume \(.applicationName)", "Keep reading in \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PausePlaybackIntent(),
            phrases: ["Pause \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: SetSleepTimerIntent(),
            phrases: ["Set a sleep timer in \(.applicationName)"],
            shortTitle: "Sleep timer",
            systemImageName: "moon"
        )
        AppShortcut(
            intent: AddBookmarkIntent(),
            phrases: ["Add a bookmark in \(.applicationName)"],
            shortTitle: "Bookmark",
            systemImageName: "bookmark"
        )
    }
}
