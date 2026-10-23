import Foundation

/// A parsed Audiobookshelf server version.
///
/// ABS reports its version from `GET /status` as `serverVersion`, e.g. `2.17.5`.
/// Pre-release suffixes (`2.26.0-beta.1`) are kept but ignored when ordering, so
/// a beta of a release compares equal to the release itself. That is deliberate:
/// a user running `2.26.0-beta.1` has the 2.26.0 endpoints.
public struct ServerVersion: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses a version string, tolerating a leading `v` and missing components.
    /// Returns `nil` only when there is no leading integer to read.
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        let core: String
        var suffix: String?
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = String(text[text.startIndex..<cut])
            let rest = String(text[text.index(after: cut)...])
            suffix = rest.isEmpty ? nil : rest
        } else {
            core = text
        }

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = parts.first, let major = Int(first) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        self.patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        self.prerelease = suffix
    }

    public static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// Equality ignores the pre-release suffix, matching the ordering rule.
    public static func == (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.map { "\(core)-\($0)" } ?? core
    }
}
