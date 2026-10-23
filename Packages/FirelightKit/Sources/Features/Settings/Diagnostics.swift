import ABSKit
import Foundation
import Persistence

/// A report the user can send when something is wrong.
///
/// Working rule 7 is absolute here: a diagnostics file is the most likely
/// thing in the app to be pasted into a public issue tracker, so it carries
/// no token, no password, no username and no server address. Everything that
/// could identify a server is replaced, not shortened.
public enum DiagnosticsReport {
    public struct Input: Sendable {
        public let appVersion: String
        public let build: String
        public let systemVersion: String
        public let deviceModel: String
        public let serverCount: Int
        public let serverVersions: [String]
        public let activeAddressKind: String?
        public let isOffline: Bool
        public let libraryItemCount: Int
        public let queuedProgressCount: Int
        public let downloadCount: Int
        public let downloadBytes: Int64
        public let appGroupAvailable: Bool
        public let keychainAvailable: Bool
        public let databaseAvailable: Bool

        public init(
            appVersion: String,
            build: String,
            systemVersion: String,
            deviceModel: String,
            serverCount: Int,
            serverVersions: [String],
            activeAddressKind: String?,
            isOffline: Bool,
            libraryItemCount: Int,
            queuedProgressCount: Int,
            downloadCount: Int,
            downloadBytes: Int64,
            appGroupAvailable: Bool,
            keychainAvailable: Bool,
            databaseAvailable: Bool
        ) {
            self.appVersion = appVersion
            self.build = build
            self.systemVersion = systemVersion
            self.deviceModel = deviceModel
            self.serverCount = serverCount
            self.serverVersions = serverVersions
            self.activeAddressKind = activeAddressKind
            self.isOffline = isOffline
            self.libraryItemCount = libraryItemCount
            self.queuedProgressCount = queuedProgressCount
            self.downloadCount = downloadCount
            self.downloadBytes = downloadBytes
            self.appGroupAvailable = appGroupAvailable
            self.keychainAvailable = keychainAvailable
            self.databaseAvailable = databaseAvailable
        }
    }

    public static func text(from input: Input, generatedAt: Date = .now) -> String {
        """
        Firelight diagnostics
        Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))

        App
          Version          \(input.appVersion) (\(input.build))
          iOS              \(input.systemVersion)
          Device           \(input.deviceModel)

        Servers
          Configured       \(input.serverCount)
          Versions         \(input.serverVersions.isEmpty ? "unknown" : input.serverVersions.joined(separator: ", "))
          Active address   \(input.activeAddressKind ?? "none")
          Reachable        \(input.isOffline ? "no" : "yes")

        Data
          Cached items     \(input.libraryItemCount)
          Progress queued  \(input.queuedProgressCount)
          Downloads        \(input.downloadCount) (\(input.downloadBytes) bytes)

        Foundation
          App Group        \(yesNo(input.appGroupAvailable))
          Keychain         \(yesNo(input.keychainAvailable))
          Database         \(yesNo(input.databaseAvailable))

        No server addresses, usernames or tokens are included in this report.
        """
    }

    private static func yesNo(_ value: Bool) -> String { value ? "working" : "not working" }

    /// Belt and braces: if anything ever leaks into the text, it does not
    /// leave the device. Checked by a test.
    public static func containsSensitiveData(_ report: String, knownSecrets: [String]) -> Bool {
        let lowercased = report.lowercased()
        for secret in knownSecrets where !secret.isEmpty {
            if lowercased.contains(secret.lowercased()) { return true }
        }
        // A URL with a host would be an address; the report should have none.
        return lowercased.contains("http://") || lowercased.contains("https://")
    }

    public static func write(_ text: String) -> URL? {
        let url = URL.temporaryDirectory.appending(path: "Firelight Diagnostics.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
