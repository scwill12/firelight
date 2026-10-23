import Foundation

public enum SmartShelfKind: String, Sendable, Hashable, CaseIterable, Codable {
    case recentlyPlayed
    case nextInSeries
    case unfinishedSeries
    case recentlyAdded
    case abandoned
    case shortListens
}

public struct SmartShelf: Sendable, Hashable, Identifiable {
    public let kind: SmartShelfKind
    public let items: [LibraryItemSummary]

    public var id: String { kind.rawValue }

    public init(kind: SmartShelfKind, items: [LibraryItemSummary]) {
        self.kind = kind
        self.items = items
    }
}

/// Builds the home screen's shelves from the cached library.
///
/// Entirely local: these shelves are Firelight's, not the server's
/// `/personalized` ones, which means they are instant and work on a plane.
/// Pure input-to-output so every rule below is testable without a server.
public struct SmartShelfBuilder: Sendable {
    /// Started, then untouched for this long, counts as abandoned.
    public var abandonedAfter: TimeInterval
    /// "Short listens" ceiling.
    public var shortListenCeiling: TimeInterval
    public var maxItemsPerShelf: Int

    public init(
        abandonedAfter: TimeInterval = 30 * 24 * 3600,
        shortListenCeiling: TimeInterval = 5 * 3600,
        maxItemsPerShelf: Int = 20
    ) {
        self.abandonedAfter = abandonedAfter
        self.shortListenCeiling = shortListenCeiling
        self.maxItemsPerShelf = maxItemsPerShelf
    }

    /// The one item the home screen leads with: whatever you most recently
    /// made progress in and have not finished.
    public func currentItem(from items: [LibraryItemSummary]) -> LibraryItemSummary? {
        items
            .filter { $0.isStarted && !$0.isHiddenFromContinue && !$0.isMissing }
            .max { lastPlayed($0) < lastPlayed($1) }
    }

    public func shelves(from items: [LibraryItemSummary], now: Date = .now) -> [SmartShelf] {
        let available = items.filter { !$0.isMissing }
        let hero = currentItem(from: available)

        let nextInSeries = nextInSeriesItems(from: available)
        let nextIDs = Set(nextInSeries.map(\.id))

        let candidates: [(SmartShelfKind, [LibraryItemSummary])] = [
            (.recentlyPlayed, recentlyPlayed(from: available, excluding: hero)),
            (.nextInSeries, nextInSeries),
            (.unfinishedSeries, unfinishedSeries(from: available, excluding: nextIDs)),
            (.recentlyAdded, recentlyAdded(from: available)),
            (.abandoned, abandoned(from: available, now: now)),
            (.shortListens, shortListens(from: available)),
        ]

        // An empty shelf is clutter, not a state.
        return candidates
            .filter { !$0.1.isEmpty }
            .map { SmartShelf(kind: $0.0, items: Array($0.1.prefix(maxItemsPerShelf))) }
    }

    /// "Pick something for me" — an unstarted book, at random.
    public func pickForMe(from items: [LibraryItemSummary], using generator: inout some RandomNumberGenerator) -> LibraryItemSummary? {
        let unstarted = items.filter { !$0.isStarted && !$0.isFinished && !$0.isMissing }
        return (unstarted.isEmpty ? items.filter { !$0.isMissing } : unstarted).randomElement(using: &generator)
    }

    public func pickForMe(from items: [LibraryItemSummary]) -> LibraryItemSummary? {
        var generator = SystemRandomNumberGenerator()
        return pickForMe(from: items, using: &generator)
    }

    // MARK: - Shelves

    func recentlyPlayed(from items: [LibraryItemSummary], excluding hero: LibraryItemSummary?) -> [LibraryItemSummary] {
        items
            .filter { $0.progressLastUpdate != nil && $0.id != hero?.id && !$0.isHiddenFromContinue }
            .filter { $0.isStarted || $0.isFinished }
            .sorted { lastPlayed($0) > lastPlayed($1) }
    }

    /// The book after the furthest one you have finished in each series.
    func nextInSeriesItems(from items: [LibraryItemSummary]) -> [LibraryItemSummary] {
        var result: [LibraryItemSummary] = []

        for (_, booksInSeries) in Dictionary(grouping: items.filter { $0.seriesBaseName != nil }, by: { $0.seriesBaseName! }) {
            let ordered = booksInSeries.sorted { sequence($0) < sequence($1) }
            guard let furthestFinished = ordered.last(where: { $0.isFinished }) else { continue }
            // Nothing in progress: if you are already reading one, that is what
            // Continue is for, not this shelf.
            guard !ordered.contains(where: { $0.isStarted }) else { continue }

            if let next = ordered.first(where: { sequence($0) > sequence(furthestFinished) && !$0.isFinished }) {
                result.append(next)
            }
        }
        return result.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
    }

    /// Series you are partway through, surfaced by their earliest unfinished
    /// book. Excludes anything already shown as Next in series.
    func unfinishedSeries(from items: [LibraryItemSummary], excluding excluded: Set<String>) -> [LibraryItemSummary] {
        var result: [LibraryItemSummary] = []

        for (_, booksInSeries) in Dictionary(grouping: items.filter { $0.seriesBaseName != nil }, by: { $0.seriesBaseName! }) {
            let touched = booksInSeries.contains { $0.isFinished || $0.isStarted }
            guard touched, booksInSeries.contains(where: { !$0.isFinished }) else { continue }

            let ordered = booksInSeries.sorted { sequence($0) < sequence($1) }
            if let earliestUnfinished = ordered.first(where: { !$0.isFinished && !excluded.contains($0.id) }) {
                result.append(earliestUnfinished)
            }
        }
        return result.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
    }

    func recentlyAdded(from items: [LibraryItemSummary]) -> [LibraryItemSummary] {
        items
            .filter { !$0.isFinished }
            .sorted { $0.addedAt > $1.addedAt }
    }

    /// Started, then left alone for a month.
    func abandoned(from items: [LibraryItemSummary], now: Date) -> [LibraryItemSummary] {
        items
            .filter { $0.isStarted && !$0.isHiddenFromContinue }
            .filter { item in
                guard let lastUpdate = item.progressLastUpdate else { return false }
                return now.timeIntervalSince(lastUpdate) >= abandonedAfter
            }
            .sorted { lastPlayed($0) > lastPlayed($1) }
    }

    func shortListens(from items: [LibraryItemSummary]) -> [LibraryItemSummary] {
        items
            .filter { !$0.isStarted && !$0.isFinished }
            .filter { $0.duration > 0 && $0.duration < shortListenCeiling }
            .sorted { $0.duration < $1.duration }
    }

    // MARK: - Helpers

    private func lastPlayed(_ item: LibraryItemSummary) -> Date {
        item.progressLastUpdate ?? item.progressStartedAt ?? .distantPast
    }

    /// Unnumbered books sort to the end of their series rather than the front.
    private func sequence(_ item: LibraryItemSummary) -> Double {
        item.seriesSequence ?? .greatestFiniteMagnitude
    }
}
