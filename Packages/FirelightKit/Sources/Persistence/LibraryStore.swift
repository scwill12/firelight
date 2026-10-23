import ABSKit
import Foundation
import SwiftData

/// A library item as the UI holds it: a value, never a SwiftData object.
public struct LibraryItemSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let serverID: UUID
    public let libraryID: String
    public let title: String
    public let sortTitle: String
    public let subtitle: String?
    public let author: String?
    public let narrator: String?
    public let seriesName: String?
    public let seriesBaseName: String?
    public let seriesSequence: Double?
    public let genres: [String]
    public let publishedYear: String?
    public let summary: String?
    public let duration: TimeInterval
    public let sizeBytes: Int64
    public let numChapters: Int
    public let ebookFormat: String?
    public let hasAudio: Bool
    public let coverPath: String?
    public let mediaType: String
    public let isMissing: Bool
    public let addedAt: Date
    public let updatedAt: Date

    public let progressCurrentTime: TimeInterval
    public let progressFraction: Double
    public let isFinished: Bool
    public let progressLastUpdate: Date?
    public let progressStartedAt: Date?
    public let isHiddenFromContinue: Bool

    public var hasEbook: Bool { ebookFormat?.isEmpty == false }
    public var isStarted: Bool { progressFraction > 0.001 && !isFinished }
    public var remainingTime: TimeInterval { max(0, duration - progressCurrentTime) }

    /// "under 5 hours", per the spec's Short listens shelf.
    public var isShortListen: Bool { duration > 0 && duration < 5 * 3600 }
}

public struct LibrarySummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let serverID: UUID
    public let name: String
    public let mediaType: String?
    public let displayOrder: Int
    public let lastRefreshedAt: Date?

    public var isPodcast: Bool { mediaType == "podcast" }
}

/// How a browse list is ordered.
public enum LibrarySort: String, Sendable, CaseIterable, Codable {
    case title
    case author
    case addedAt
    case duration
    case progress
}

/// Reads and writes the cached library. Every screen reads from here first,
/// which is what makes the app open instantly and work on a plane.
@ModelActor
public actor LibraryStore {
    // MARK: - Writing

    public func replaceLibraries(serverID: UUID, with libraries: [ABSLibrary]) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedLibrary>(predicate: #Predicate { $0.serverID == serverID })
        )
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.libraryID, $0) })

        for (index, library) in libraries.enumerated() {
            if let record = byID.removeValue(forKey: library.id) {
                record.name = library.name
                record.mediaType = library.mediaType
                record.displayOrder = library.displayOrder ?? index
            } else {
                modelContext.insert(CachedLibrary(
                    serverID: serverID,
                    libraryID: library.id,
                    name: library.name,
                    mediaType: library.mediaType,
                    displayOrder: library.displayOrder ?? index
                ))
            }
        }
        // Anything left was removed on the server.
        for orphan in byID.values { modelContext.delete(orphan) }
        try modelContext.save()
    }

    /// Inserts or updates items, preserving the progress already cached for
    /// them — a library refresh must never blank out where someone is.
    /// ABS sends `""` for absent metadata rather than `null` — confirmed
    /// against a real 2.37.1 server. An empty string survives `if let`, so it
    /// reaches the UI as a blank row and a facet with no name. Normalise at
    /// the boundary, once.
    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    public func upsertItems(serverID: UUID, items: [ABSLibraryItem]) throws {
        guard !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedItem>(
                predicate: #Predicate { $0.serverID == serverID && ids.contains($0.itemID) }
            )
        )
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.itemID, $0) })

        for item in items {
            let metadata = item.media?.metadata
            let series = SeriesNameParser.parse(Self.nonEmpty(metadata?.seriesName))
            let title = metadata?.title ?? "Untitled"

            if let record = byID[item.id] {
                record.libraryID = item.libraryId ?? record.libraryID
                record.title = title
                record.sortTitle = metadata?.titleIgnorePrefix ?? title
                record.subtitle = Self.nonEmpty(metadata?.subtitle)
                record.author = Self.nonEmpty(metadata?.authorName)
                record.narrator = Self.nonEmpty(metadata?.narratorName)
                record.seriesName = Self.nonEmpty(metadata?.seriesName)
                record.seriesBaseName = series.name
                record.seriesSequence = series.sequence
                record.genresText = (metadata?.genres ?? []).joined(separator: ", ")
                record.refreshSearchText()
                record.publishedYear = Self.nonEmpty(metadata?.publishedYear)
                record.summary = Self.nonEmpty(metadata?.description)
                record.duration = item.media?.duration ?? 0
                record.sizeBytes = item.size ?? item.media?.size ?? 0
                record.numChapters = item.media?.numChapters ?? 0
                record.ebookFormat = Self.nonEmpty(item.media?.ebookFormat)
                record.hasAudio = (item.media?.numTracks ?? 0) > 0
                record.coverPath = item.media?.coverPath
                record.mediaType = item.mediaType ?? "book"
                record.isMissing = item.isMissing ?? false
                record.addedAt = item.addedAt ?? record.addedAt
                record.updatedAt = item.updatedAt ?? record.updatedAt
            } else {
                modelContext.insert(CachedItem(
                    serverID: serverID,
                    itemID: item.id,
                    libraryID: item.libraryId ?? "",
                    title: title,
                    sortTitle: metadata?.titleIgnorePrefix ?? title,
                    subtitle: Self.nonEmpty(metadata?.subtitle),
                    author: Self.nonEmpty(metadata?.authorName),
                    narrator: Self.nonEmpty(metadata?.narratorName),
                    seriesName: Self.nonEmpty(metadata?.seriesName),
                    seriesBaseName: series.name,
                    seriesSequence: series.sequence,
                    genresText: (metadata?.genres ?? []).joined(separator: ", "),
                    publishedYear: Self.nonEmpty(metadata?.publishedYear),
                    summary: Self.nonEmpty(metadata?.description),
                    duration: item.media?.duration ?? 0,
                    sizeBytes: item.size ?? item.media?.size ?? 0,
                    numChapters: item.media?.numChapters ?? 0,
                    ebookFormat: Self.nonEmpty(item.media?.ebookFormat),
                    hasAudio: (item.media?.numTracks ?? 0) > 0,
                    coverPath: item.media?.coverPath,
                    mediaType: item.mediaType ?? "book",
                    isMissing: item.isMissing ?? false,
                    addedAt: item.addedAt ?? .now,
                    updatedAt: item.updatedAt ?? .now
                ))
            }
        }
        try modelContext.save()
    }

    /// Applies the server's progress to cached items.
    public func applyProgress(serverID: UUID, progress: [ABSMediaProgress]) throws {
        guard !progress.isEmpty else { return }
        // Books only for now; episode progress needs the podcast models (Phase 11).
        let byItem = Dictionary(
            progress.compactMap { entry -> (String, ABSMediaProgress)? in
                guard let itemID = entry.libraryItemId, entry.episodeId == nil else { return nil }
                return (itemID, entry)
            },
            uniquingKeysWith: { first, second in
                (second.lastUpdate ?? .distantPast) > (first.lastUpdate ?? .distantPast) ? second : first
            }
        )
        let ids = Set(byItem.keys)
        guard !ids.isEmpty else { return }

        let records = try modelContext.fetch(
            FetchDescriptor<CachedItem>(
                predicate: #Predicate { $0.serverID == serverID && ids.contains($0.itemID) }
            )
        )
        for record in records {
            guard let entry = byItem[record.itemID] else { continue }
            record.progressCurrentTime = entry.currentTime ?? 0
            record.progressFraction = min(max(entry.progress ?? 0, 0), 1)
            record.progressIsFinished = entry.isFinished ?? false
            record.progressLastUpdate = entry.lastUpdate
            record.progressStartedAt = entry.startedAt
            record.progressHidden = entry.hideFromContinueListening ?? false
        }
        try modelContext.save()
    }

    /// Drops cached items the server no longer has.
    public func pruneItems(serverID: UUID, libraryID: String, keeping keptIDs: Set<String>) throws {
        let records = try modelContext.fetch(
            FetchDescriptor<CachedItem>(
                predicate: #Predicate { $0.serverID == serverID && $0.libraryID == libraryID }
            )
        )
        var removed = false
        for record in records where !keptIDs.contains(record.itemID) {
            modelContext.delete(record)
            removed = true
        }
        if removed { try modelContext.save() }
    }

    public func markRefreshed(serverID: UUID, libraryID: String, at date: Date = .now) throws {
        let composite = "\(serverID.uuidString):\(libraryID)"
        let records = try modelContext.fetch(
            FetchDescriptor<CachedLibrary>(predicate: #Predicate { $0.compositeID == composite })
        )
        records.first?.lastRefreshedAt = date
        try modelContext.save()
    }

    public func removeEverything(serverID: UUID) throws {
        for item in try modelContext.fetch(
            FetchDescriptor<CachedItem>(predicate: #Predicate { $0.serverID == serverID })
        ) { modelContext.delete(item) }
        for library in try modelContext.fetch(
            FetchDescriptor<CachedLibrary>(predicate: #Predicate { $0.serverID == serverID })
        ) { modelContext.delete(library) }
        try modelContext.save()
    }

    // MARK: - Reading

    public func libraries(serverID: UUID) throws -> [LibrarySummary] {
        try modelContext.fetch(
            FetchDescriptor<CachedLibrary>(
                predicate: #Predicate { $0.serverID == serverID },
                sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.name)]
            )
        ).map(Self.summary(from:))
    }

    public func itemCount(serverID: UUID) throws -> Int {
        try modelContext.fetchCount(
            FetchDescriptor<CachedItem>(predicate: #Predicate { $0.serverID == serverID })
        )
    }

    public func items(
        serverID: UUID,
        libraryID: String? = nil,
        sort: LibrarySort = .title,
        descending: Bool = false,
        limit: Int? = nil
    ) throws -> [LibraryItemSummary] {
        var descriptor = FetchDescriptor<CachedItem>(
            predicate: Self.predicate(serverID: serverID, libraryID: libraryID),
            sortBy: Self.sortDescriptors(sort, descending: descending)
        )
        if let limit { descriptor.fetchLimit = limit }
        return try modelContext.fetch(descriptor).map(Self.summary(from:))
    }

    public func item(serverID: UUID, itemID: String) throws -> LibraryItemSummary? {
        let composite = "\(serverID.uuidString):\(itemID)"
        return try modelContext.fetch(
            FetchDescriptor<CachedItem>(predicate: #Predicate { $0.compositeID == composite })
        ).first.map(Self.summary(from:))
    }

    /// Cache-first search across title, author, narrator, series and genre.
    ///
    /// Matches against the denormalised, diacritic-folded `searchText`, so
    /// "bronte" finds "Brontë" and one predicate covers every field.
    public func search(serverID: UUID, query: String, limit: Int = 50) throws -> [LibraryItemSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        // Fold the needle the same way the haystack was folded at write time.
        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        var descriptor = FetchDescriptor<CachedItem>(
            predicate: #Predicate {
                $0.serverID == serverID && $0.searchText.contains(needle)
            },
            sortBy: [SortDescriptor(\.sortTitle)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(Self.summary(from:))
    }

    /// Distinct values for the browse-by pickers.
    public func facetValues(serverID: UUID, facet: LibraryFacet, libraryID: String? = nil) throws -> [String] {
        let items = try modelContext.fetch(
            FetchDescriptor<CachedItem>(predicate: Self.predicate(serverID: serverID, libraryID: libraryID))
        )
        var values = Set<String>()
        for item in items {
            switch facet {
            case .author:
                if let author = item.author, !author.isEmpty { values.insert(author) }
            case .narrator:
                if let narrator = item.narrator, !narrator.isEmpty { values.insert(narrator) }
            case .series:
                if let series = item.seriesBaseName, !series.isEmpty { values.insert(series) }
            case .genre:
                for genre in item.genresText.split(separator: ",") {
                    let trimmed = genre.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { values.insert(trimmed) }
                }
            }
        }
        return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func items(serverID: UUID, matching facet: LibraryFacet, value: String) throws -> [LibraryItemSummary] {
        let all = try modelContext.fetch(
            FetchDescriptor<CachedItem>(predicate: #Predicate { $0.serverID == serverID })
        )
        let matched = all.filter { item in
            switch facet {
            case .author: item.author == value
            case .narrator: item.narrator == value
            case .series: item.seriesBaseName == value
            case .genre: item.genresText.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == value }
            }
        }
        let summaries = matched.map(Self.summary(from:))
        // A series reads in series order; everything else reads alphabetically.
        if facet == .series {
            return summaries.sorted {
                ($0.seriesSequence ?? .greatestFiniteMagnitude, $0.sortTitle)
                    < ($1.seriesSequence ?? .greatestFiniteMagnitude, $1.sortTitle)
            }
        }
        return summaries.sorted { $0.sortTitle.localizedStandardCompare($1.sortTitle) == .orderedAscending }
    }

    // MARK: - Private

    private static func predicate(serverID: UUID, libraryID: String?) -> Predicate<CachedItem> {
        if let libraryID {
            return #Predicate { $0.serverID == serverID && $0.libraryID == libraryID }
        }
        return #Predicate { $0.serverID == serverID }
    }

    private static func sortDescriptors(_ sort: LibrarySort, descending: Bool) -> [SortDescriptor<CachedItem>] {
        let order: SortOrder = descending ? .reverse : .forward
        return switch sort {
        case .title: [SortDescriptor(\.sortTitle, order: order)]
        case .author: [SortDescriptor(\.author, order: order), SortDescriptor(\.sortTitle)]
        case .addedAt: [SortDescriptor(\.addedAt, order: descending ? .forward : .reverse)]
        case .duration: [SortDescriptor(\.duration, order: order)]
        case .progress: [SortDescriptor(\.progressFraction, order: descending ? .forward : .reverse)]
        }
    }

    private static func summary(from record: CachedItem) -> LibraryItemSummary {
        LibraryItemSummary(
            id: record.itemID,
            serverID: record.serverID,
            libraryID: record.libraryID,
            title: record.title,
            sortTitle: record.sortTitle,
            subtitle: record.subtitle,
            author: record.author,
            narrator: record.narrator,
            seriesName: record.seriesName,
            seriesBaseName: record.seriesBaseName,
            seriesSequence: record.seriesSequence,
            genres: record.genresText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            publishedYear: record.publishedYear,
            summary: record.summary,
            duration: record.duration,
            sizeBytes: record.sizeBytes,
            numChapters: record.numChapters,
            ebookFormat: record.ebookFormat,
            hasAudio: record.hasAudio,
            coverPath: record.coverPath,
            mediaType: record.mediaType,
            isMissing: record.isMissing,
            addedAt: record.addedAt,
            updatedAt: record.updatedAt,
            progressCurrentTime: record.progressCurrentTime,
            progressFraction: record.progressFraction,
            isFinished: record.progressIsFinished,
            progressLastUpdate: record.progressLastUpdate,
            progressStartedAt: record.progressStartedAt,
            isHiddenFromContinue: record.progressHidden
        )
    }

    private static func summary(from record: CachedLibrary) -> LibrarySummary {
        LibrarySummary(
            id: record.libraryID,
            serverID: record.serverID,
            name: record.name,
            mediaType: record.mediaType,
            displayOrder: record.displayOrder,
            lastRefreshedAt: record.lastRefreshedAt
        )
    }
}

/// An episode as the UI holds it.
public struct EpisodeSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let itemID: String
    public let episodeID: String
    public let title: String
    public let subtitle: String?
    public let summary: String?
    public let numbering: String?
    public let duration: TimeInterval
    public let sizeBytes: Int64
    public let publishedAt: Date?
    public let progressCurrentTime: TimeInterval
    public let progressFraction: Double
    public let isFinished: Bool

    public var isStarted: Bool { progressFraction > 0.001 && !isFinished }
    public var isUnplayed: Bool { !isStarted && !isFinished }
    public var remainingTime: TimeInterval { max(0, duration - progressCurrentTime) }
}

public extension LibraryStore {
    /// Replaces a show's episode list with what the server just sent.
    func replaceEpisodes(
        serverID: UUID,
        itemID: String,
        episodes: [(episodeID: String, title: String, subtitle: String?, summary: String?,
                    numbering: String?, duration: Double, sizeBytes: Int64,
                    publishedAt: Date?, feedIndex: Int)]
    ) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<CachedEpisode>(
                predicate: #Predicate { $0.serverID == serverID && $0.itemID == itemID }
            )
        )
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.episodeID, $0) })

        for episode in episodes {
            if let record = byID.removeValue(forKey: episode.episodeID) {
                record.title = episode.title
                record.subtitle = episode.subtitle
                record.summary = episode.summary
                record.numbering = episode.numbering
                record.duration = episode.duration
                record.sizeBytes = episode.sizeBytes
                record.publishedAt = episode.publishedAt
                record.feedIndex = episode.feedIndex
            } else {
                modelContext.insert(CachedEpisode(
                    serverID: serverID, itemID: itemID, episodeID: episode.episodeID,
                    title: episode.title, subtitle: episode.subtitle, summary: episode.summary,
                    numbering: episode.numbering, duration: episode.duration,
                    sizeBytes: episode.sizeBytes, publishedAt: episode.publishedAt,
                    feedIndex: episode.feedIndex
                ))
            }
        }
        // Anything the feed dropped.
        for orphan in byID.values { modelContext.delete(orphan) }
        try modelContext.save()
    }

    /// Newest first, which is how a podcast is read.
    func episodes(serverID: UUID, itemID: String) throws -> [EpisodeSummary] {
        try modelContext.fetch(
            FetchDescriptor<CachedEpisode>(
                predicate: #Predicate { $0.serverID == serverID && $0.itemID == itemID },
                sortBy: [
                    SortDescriptor(\.publishedAt, order: .reverse),
                    SortDescriptor(\.feedIndex, order: .reverse),
                ]
            )
        ).map(Self.summary(from:))
    }

    /// Applies the server's episode progress.
    func applyEpisodeProgress(serverID: UUID, progress: [ABSMediaProgress]) throws {
        let byEpisode = Dictionary(
            progress.compactMap { entry -> (String, ABSMediaProgress)? in
                guard let itemID = entry.libraryItemId, let episodeID = entry.episodeId else { return nil }
                return ("\(itemID):\(episodeID)", entry)
            },
            uniquingKeysWith: { first, second in
                (second.lastUpdate ?? .distantPast) > (first.lastUpdate ?? .distantPast) ? second : first
            }
        )
        guard !byEpisode.isEmpty else { return }

        for record in try modelContext.fetch(
            FetchDescriptor<CachedEpisode>(predicate: #Predicate { $0.serverID == serverID })
        ) {
            guard let entry = byEpisode["\(record.itemID):\(record.episodeID)"] else { continue }
            record.progressCurrentTime = entry.currentTime ?? 0
            record.progressFraction = min(max(entry.progress ?? 0, 0), 1)
            record.isFinished = entry.isFinished ?? false
            record.progressLastUpdate = entry.lastUpdate
        }
        try modelContext.save()
    }

    private static func summary(from record: CachedEpisode) -> EpisodeSummary {
        EpisodeSummary(
            id: record.compositeID,
            itemID: record.itemID,
            episodeID: record.episodeID,
            title: record.title,
            subtitle: record.subtitle,
            summary: record.summary,
            numbering: record.numbering,
            duration: record.duration,
            sizeBytes: record.sizeBytes,
            publishedAt: record.publishedAt,
            progressCurrentTime: record.progressCurrentTime,
            progressFraction: record.progressFraction,
            isFinished: record.isFinished
        )
    }
}

public enum LibraryFacet: String, Sendable, CaseIterable, Codable {
    case author
    case narrator
    case series
    case genre
}
