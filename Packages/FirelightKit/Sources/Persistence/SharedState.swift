import Foundation

/// The handful of values the extensions need without opening the database.
///
/// A widget gets a few milliseconds and a share extension gets a cold start;
/// neither should pay for a SwiftData container to answer "is a server set up?".
/// The app writes these on launch and whenever they change, and the extensions
/// only read.
public enum SharedState {
    private enum Key {
        static let serverCount = "firelight.shared.serverCount"
        static let lastLibraryRefresh = "firelight.shared.lastLibraryRefresh"
    }

    private static var defaults: UserDefaults? { AppGroup.defaults }

    public static var serverCount: Int {
        get { defaults?.integer(forKey: Key.serverCount) ?? 0 }
        set { defaults?.set(newValue, forKey: Key.serverCount) }
    }

    public static var hasConfiguredServer: Bool { serverCount > 0 }

    public static var lastLibraryRefresh: Date? {
        get {
            guard let seconds = defaults?.object(forKey: Key.lastLibraryRefresh) as? Double else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        set {
            if let newValue {
                defaults?.set(newValue.timeIntervalSince1970, forKey: Key.lastLibraryRefresh)
            } else {
                defaults?.removeObject(forKey: Key.lastLibraryRefresh)
            }
        }
    }
}
