import Foundation

/// The one container every Firelight target shares.
///
/// The app, the widgets, the share extension and the watch app all read the
/// same SwiftData store and the same defaults, so none of them can disagree
/// about what the user is listening to.
public enum AppGroup {
    public static let identifier = "group.com.colewilliams.firelight"

    /// `nil` only when the App Group capability is missing from the running
    /// target's entitlements, which is a build configuration error rather than
    /// something to recover from at runtime.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// Where the SwiftData store lives.
    public static func storeURL() throws -> URL {
        guard let containerURL else { throw PersistenceError.appGroupUnavailable }
        let directory = containerURL.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Firelight.store")
    }

    /// Where downloaded audio and ebook files go. Excluded from backup: these
    /// are re-downloadable, and a 40 GB library has no business in an iCloud
    /// backup.
    public static func downloadsURL() throws -> URL {
        guard let containerURL else { throw PersistenceError.appGroupUnavailable }
        let directory = containerURL.appending(path: "Downloads", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutable = directory
            try mutable.setResourceValues(resourceValues)
        }
        return directory
    }
}

public enum PersistenceError: Error, Sendable, Equatable {
    case appGroupUnavailable
    case storeUnavailable(String)
}
