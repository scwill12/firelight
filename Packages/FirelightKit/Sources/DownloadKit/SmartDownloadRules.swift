import Foundation

/// What Firelight downloads and removes on its own.
///
/// Pure rules, so "does it fetch the next book yet?" is a test rather than a
/// week of waiting. Automatic behaviour around someone's storage has to be
/// predictable, and predictable means testable.
public struct SmartDownloadRules: Sendable, Hashable, Codable {
    /// Fetch the next book in a series once the current one passes this.
    public var nextInSeriesThreshold: Double
    /// Remove a finished download after this many days. Zero means never.
    public var removeFinishedAfterDays: Int
    public var isAutoDownloadEnabled: Bool
    public var isAutoRemoveEnabled: Bool
    /// Default on, per the spec: nobody wants a 2 GB book on cellular.
    public var wifiOnly: Bool

    public static let `default` = SmartDownloadRules(
        nextInSeriesThreshold: 0.8,
        removeFinishedAfterDays: 7,
        isAutoDownloadEnabled: false,
        isAutoRemoveEnabled: false,
        wifiOnly: true
    )

    public init(
        nextInSeriesThreshold: Double,
        removeFinishedAfterDays: Int,
        isAutoDownloadEnabled: Bool,
        isAutoRemoveEnabled: Bool,
        wifiOnly: Bool
    ) {
        self.nextInSeriesThreshold = nextInSeriesThreshold
        self.removeFinishedAfterDays = removeFinishedAfterDays
        self.isAutoDownloadEnabled = isAutoDownloadEnabled
        self.isAutoRemoveEnabled = isAutoRemoveEnabled
        self.wifiOnly = wifiOnly
    }

    /// The minimum a candidate needs for the rules to reason about it.
    public struct Candidate: Sendable, Hashable {
        public let itemID: String
        public let seriesBaseName: String?
        public let seriesSequence: Double?
        public let progressFraction: Double
        public let isFinished: Bool
        public let isDownloaded: Bool
        public let finishedAt: Date?

        public init(
            itemID: String,
            seriesBaseName: String?,
            seriesSequence: Double?,
            progressFraction: Double,
            isFinished: Bool,
            isDownloaded: Bool,
            finishedAt: Date? = nil
        ) {
            self.itemID = itemID
            self.seriesBaseName = seriesBaseName
            self.seriesSequence = seriesSequence
            self.progressFraction = progressFraction
            self.isFinished = isFinished
            self.isDownloaded = isDownloaded
            self.finishedAt = finishedAt
        }
    }

    /// Which books to fetch next.
    ///
    /// Only the book immediately after one you are nearly through, and only
    /// when it is not already here. Downloading a whole series unasked is a
    /// way to fill someone's phone.
    public func itemsToDownload(from candidates: [Candidate]) -> [String] {
        guard isAutoDownloadEnabled else { return [] }

        var result: [String] = []
        let bySeries = Dictionary(grouping: candidates.filter { $0.seriesBaseName != nil }) {
            $0.seriesBaseName!
        }

        for (_, booksInSeries) in bySeries {
            let ordered = booksInSeries.sorted {
                ($0.seriesSequence ?? .greatestFiniteMagnitude) < ($1.seriesSequence ?? .greatestFiniteMagnitude)
            }
            guard let current = ordered.last(where: {
                $0.progressFraction >= nextInSeriesThreshold || $0.isFinished
            }) else { continue }

            let currentSequence = current.seriesSequence ?? .greatestFiniteMagnitude
            guard let next = ordered.first(where: {
                ($0.seriesSequence ?? .greatestFiniteMagnitude) > currentSequence
                && !$0.isFinished
                && !$0.isDownloaded
            }) else { continue }

            result.append(next.itemID)
        }
        return result.sorted()
    }

    /// Which downloads have outstayed their welcome.
    public func itemsToRemove(from candidates: [Candidate], now: Date = .now) -> [String] {
        guard isAutoRemoveEnabled, removeFinishedAfterDays > 0 else { return [] }
        let cutoff = TimeInterval(removeFinishedAfterDays) * 86_400

        return candidates
            .filter { $0.isDownloaded && $0.isFinished }
            .filter { candidate in
                guard let finishedAt = candidate.finishedAt else { return false }
                return now.timeIntervalSince(finishedAt) >= cutoff
            }
            .map(\.itemID)
            .sorted()
    }

    /// Whether a download may start on the current connection.
    public func allowsDownload(onExpensiveConnection isExpensive: Bool) -> Bool {
        !(wifiOnly && isExpensive)
    }
}

/// Human-readable sizes.
public enum StorageFormatter {
    /// Built per call rather than shared: `ByteCountFormatter` is a mutable
    /// class and not `Sendable`, and formatting a handful of sizes is cheap.
    public static func string(fromBytes bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
