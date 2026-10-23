import Foundation
import SwiftData
import Testing
@testable import ABSKit
@testable import Features
@testable import Persistence

// MARK: - Fixtures

private func item(
    id: String,
    title: String,
    author: String? = "An Author",
    narrator: String? = nil,
    series: String? = nil,
    sequence: Double? = nil,
    duration: TimeInterval = 36_000,
    addedAt: Date = Date(timeIntervalSince1970: 1_600_000_000),
    progress: Double = 0,
    finished: Bool = false,
    lastUpdate: Date? = nil,
    hidden: Bool = false,
    missing: Bool = false
) -> LibraryItemSummary {
    LibraryItemSummary(
        id: id,
        serverID: UUID(),
        libraryID: "lib-1",
        title: title,
        sortTitle: title,
        subtitle: nil,
        author: author,
        narrator: narrator,
        seriesName: series,
        seriesBaseName: series,
        seriesSequence: sequence,
        genres: [],
        publishedYear: nil,
        summary: nil,
        duration: duration,
        sizeBytes: 0,
        numChapters: 0,
        ebookFormat: nil,
        hasAudio: true,
        coverPath: nil,
        mediaType: "book",
        isMissing: missing,
        addedAt: addedAt,
        updatedAt: addedAt,
        progressCurrentTime: duration * progress,
        progressFraction: progress,
        isFinished: finished,
        progressLastUpdate: lastUpdate,
        progressStartedAt: lastUpdate,
        isHiddenFromContinue: hidden
    )
}

@Suite("Series name parsing")
struct SeriesNameParserTests {
    @Test("Splits the display string ABS sends")
    func splitsNameAndNumber() {
        let parsed = SeriesNameParser.parse("Discworld #5")
        #expect(parsed.name == "Discworld")
        #expect(parsed.sequence == 5)
    }

    @Test("A novella keeps its decimal place in the series")
    func decimalSequence() {
        #expect(SeriesNameParser.parse("Wax and Wayne #2.5").sequence == 2.5)
    }

    @Test("An unnumbered series is still a series")
    func noNumber() {
        let parsed = SeriesNameParser.parse("The Culture")
        #expect(parsed.name == "The Culture")
        #expect(parsed.sequence == nil)
    }

    @Test("A name containing a hash is not mistaken for a number")
    func hashInName() {
        let parsed = SeriesNameParser.parse("Agent #9 Files")
        #expect(parsed.name == "Agent #9 Files")
        #expect(parsed.sequence == nil)
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(SeriesNameParser.parse(nil).name == nil)
        #expect(SeriesNameParser.parse("   ").name == nil)
    }
}

@Suite("Smart shelves")
struct SmartShelfBuilderTests {
    private let builder = SmartShelfBuilder()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Continue leads with whatever you touched last")
    func currentItem() {
        let older = item(id: "a", title: "Older", progress: 0.3, lastUpdate: now.addingTimeInterval(-3600))
        let newer = item(id: "b", title: "Newer", progress: 0.1, lastUpdate: now.addingTimeInterval(-60))
        #expect(builder.currentItem(from: [older, newer])?.id == "b")
    }

    @Test("A finished book is not something to continue")
    func finishedIsNotCurrent() {
        let done = item(id: "a", title: "Done", progress: 1, finished: true, lastUpdate: now)
        #expect(builder.currentItem(from: [done]) == nil)
    }

    @Test("Hiding from Continue on the server hides it here too")
    func respectsHidden() {
        let hidden = item(id: "a", title: "Hidden", progress: 0.4, lastUpdate: now, hidden: true)
        #expect(builder.currentItem(from: [hidden]) == nil)
    }

    @Test("A missing file is never offered")
    func skipsMissing() {
        let missing = item(id: "a", title: "Gone", progress: 0.4, lastUpdate: now, missing: true)
        #expect(builder.currentItem(from: [missing]) == nil)
    }

    @Test("Next in series is the book after the one you finished")
    func nextInSeries() {
        let items = [
            item(id: "1", title: "One", series: "Discworld", sequence: 1, finished: true, lastUpdate: now),
            item(id: "2", title: "Two", series: "Discworld", sequence: 2, finished: true, lastUpdate: now),
            item(id: "3", title: "Three", series: "Discworld", sequence: 3),
            item(id: "4", title: "Four", series: "Discworld", sequence: 4),
        ]
        let next = builder.nextInSeriesItems(from: items)
        #expect(next.map(\.id) == ["3"])
    }

    @Test("A series you are mid-book in belongs to Continue, not Next in series")
    func noNextWhileReading() {
        let items = [
            item(id: "1", title: "One", series: "Discworld", sequence: 1, finished: true, lastUpdate: now),
            item(id: "2", title: "Two", series: "Discworld", sequence: 2, progress: 0.4, lastUpdate: now),
            item(id: "3", title: "Three", series: "Discworld", sequence: 3),
        ]
        #expect(builder.nextInSeriesItems(from: items).isEmpty)
    }

    @Test("Finishing a whole series offers nothing further")
    func completedSeries() {
        let items = [
            item(id: "1", title: "One", series: "Done", sequence: 1, finished: true, lastUpdate: now),
            item(id: "2", title: "Two", series: "Done", sequence: 2, finished: true, lastUpdate: now),
        ]
        #expect(builder.nextInSeriesItems(from: items).isEmpty)
    }

    @Test("Unfinished series does not repeat what Next in series already showed")
    func noDuplicateBetweenSeriesShelves() {
        let items = [
            item(id: "1", title: "One", series: "Discworld", sequence: 1, finished: true, lastUpdate: now),
            item(id: "2", title: "Two", series: "Discworld", sequence: 2),
            item(id: "3", title: "Three", series: "Discworld", sequence: 3),
        ]
        let shelves = builder.shelves(from: items, now: now)
        let next = shelves.first { $0.kind == .nextInSeries }?.items.map(\.id) ?? []
        let unfinished = shelves.first { $0.kind == .unfinishedSeries }?.items.map(\.id) ?? []
        #expect(next == ["2"])
        #expect(!unfinished.contains("2"))
    }

    @Test("Abandoned means started and then left for a month")
    func abandoned() {
        let justNow = item(id: "a", title: "Fresh", progress: 0.3, lastUpdate: now.addingTimeInterval(-86_400))
        let longAgo = item(id: "b", title: "Stale", progress: 0.3, lastUpdate: now.addingTimeInterval(-40 * 86_400))
        let result = builder.abandoned(from: [justNow, longAgo], now: now)
        #expect(result.map(\.id) == ["b"])
    }

    @Test("Exactly 30 days counts as abandoned")
    func abandonedBoundary() {
        let exactly = item(id: "a", title: "Edge", progress: 0.3, lastUpdate: now.addingTimeInterval(-30 * 86_400))
        #expect(builder.abandoned(from: [exactly], now: now).count == 1)
    }

    @Test("Short listens are unstarted books under five hours")
    func shortListens() {
        let items = [
            item(id: "a", title: "Novella", duration: 3 * 3600),
            item(id: "b", title: "Epic", duration: 30 * 3600),
            item(id: "c", title: "Started short", duration: 2 * 3600, progress: 0.5, lastUpdate: now),
            item(id: "d", title: "Exactly five", duration: 5 * 3600),
        ]
        #expect(builder.shortListens(from: items).map(\.id) == ["a"])
    }

    @Test("Empty shelves are left out rather than shown empty")
    func noEmptyShelves() {
        let shelves = builder.shelves(from: [item(id: "a", title: "Untouched")], now: now)
        #expect(shelves.allSatisfy { !$0.items.isEmpty })
        #expect(!shelves.contains { $0.kind == .abandoned })
    }

    @Test("Shelves are capped so one shelf cannot be the whole screen")
    func capsShelfLength() {
        let many = (0..<50).map { item(id: "\($0)", title: "Book \($0)") }
        let builder = SmartShelfBuilder(maxItemsPerShelf: 10)
        for shelf in builder.shelves(from: many, now: now) {
            #expect(shelf.items.count <= 10)
        }
    }

    @Test("Pick something for me prefers what you haven't started")
    func pickForMe() {
        let items = [
            item(id: "started", title: "Started", progress: 0.5, lastUpdate: now),
            item(id: "fresh", title: "Fresh"),
        ]
        var generator = SeededGenerator(seed: 42)
        #expect(builder.pickForMe(from: items, using: &generator)?.id == "fresh")
    }

    @Test("With everything started it still picks something")
    func pickForMeFallsBack() {
        let items = [item(id: "a", title: "Only", progress: 0.5, lastUpdate: now)]
        var generator = SeededGenerator(seed: 1)
        #expect(builder.pickForMe(from: items, using: &generator)?.id == "a")
    }
}

/// Deterministic randomness, so the shuffle test asserts behaviour rather than luck.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("Library endpoints")
struct LibraryEndpointTests {
    @Test("Item paging sends what ABS validates")
    func itemsQuery() {
        let request = ABSEndpoint.libraryItems(libraryID: "lib-1", limit: 50, page: 2)
        let items = Dictionary(uniqueKeysWithValues: request.query.map { ($0.name, $0.value) })
        #expect(request.path == "/api/libraries/lib-1/items")
        #expect(items["limit"] == "50")
        #expect(items["page"] == "2")
        // Without minified a large library is a huge response.
        #expect(items["minified"] == "1")
    }

    @Test("Negative paging is clamped, because ABS answers 400 for it")
    func clampsPaging() {
        let request = ABSEndpoint.libraryItems(libraryID: "lib-1", limit: -5, page: -2)
        let items = Dictionary(uniqueKeysWithValues: request.query.map { ($0.name, $0.value) })
        #expect(items["limit"] == "0")
        #expect(items["page"] == "0")
    }

    @Test("Optional filters are only sent when set")
    func optionalFilters() {
        let plain = ABSEndpoint.libraryItems(libraryID: "x")
        #expect(!plain.query.contains { $0.name == "sort" })
        #expect(!plain.query.contains { $0.name == "desc" })

        let sorted = ABSEndpoint.libraryItems(libraryID: "x", sort: "media.metadata.title", descending: true, collapseSeries: true)
        let items = Dictionary(uniqueKeysWithValues: sorted.query.map { ($0.name, $0.value) })
        #expect(items["sort"] == "media.metadata.title")
        #expect(items["desc"] == "1")
        #expect(items["collapseseries"] == "1")
    }

    @Test("Cover path is built from the item id")
    func coverPath() {
        #expect(ABSEndpoint.coverPath(itemID: "li-9") == "/api/items/li-9/cover")
    }
}

@Suite("Library cache normalisation")
struct LibraryCacheNormalisationTests {
    private func makeStore() throws -> LibraryStore {
        let container = try ModelContainer(
            for: Schema(versionedSchema: CurrentSchema.self),
            configurations: ModelConfiguration(
                schema: Schema(versionedSchema: CurrentSchema.self),
                isStoredInMemoryOnly: true,
                // `.automatic` would switch CloudKit on, and CloudKit refuses
                // the cache models outright.
                cloudKitDatabase: .none
            )
        )
        return LibraryStore(modelContainer: container)
    }

    /// Exactly what a real 2.37.1 server sends for a book with no series,
    /// no subtitle and no ebook: empty strings, not nulls.
    private let emptyStringPayload = Data("""
    {"id":"li-1","libraryId":"lib-1","mediaType":"book","addedAt":1600000000000,
     "updatedAt":1600000000000,"isMissing":false,"size":100,
     "media":{"id":"bk-1","coverPath":"","numTracks":1,"numAudioFiles":1,
     "numChapters":8,"duration":3608.7,"size":100,"ebookFormat":"",
     "metadata":{"title":"A Book","titleIgnorePrefix":"Book, A","subtitle":"",
     "authorName":"An Author","narratorName":"","seriesName":"","genres":[],
     "publishedYear":"","description":"","explicit":false}}}
    """.utf8)

    @Test("Empty strings from the server do not reach the UI as blank rows")
    func emptyStringsBecomeNil() async throws {
        let store = try makeStore()
        let serverID = UUID()
        let item = try ABSJSON.decoder.decode(ABSLibraryItem.self, from: emptyStringPayload)
        try await store.upsertItems(serverID: serverID, items: [item])

        let summary = try #require(try await store.item(serverID: serverID, itemID: "li-1"))
        #expect(summary.title == "A Book")
        #expect(summary.author == "An Author")
        // All of these arrive as "" and must not render as empty detail rows.
        #expect(summary.subtitle == nil)
        #expect(summary.narrator == nil)
        #expect(summary.seriesName == nil)
        #expect(summary.publishedYear == nil)
        #expect(summary.summary == nil)
        #expect(summary.ebookFormat == nil)
        #expect(!summary.hasEbook, "an empty ebookFormat is not an ebook")
    }

    @Test("An empty series name does not create a nameless series facet")
    func emptySeriesIsNotAFacet() async throws {
        let store = try makeStore()
        let serverID = UUID()
        let item = try ABSJSON.decoder.decode(ABSLibraryItem.self, from: emptyStringPayload)
        try await store.upsertItems(serverID: serverID, items: [item])

        #expect(try await store.facetValues(serverID: serverID, facet: .series).isEmpty)
        #expect(try await store.facetValues(serverID: serverID, facet: .narrator).isEmpty)
        #expect(try await store.facetValues(serverID: serverID, facet: .author) == ["An Author"])
    }

    @Test("Whitespace-only metadata is treated as absent too")
    func whitespaceIsAbsent() async throws {
        let store = try makeStore()
        let serverID = UUID()
        let json = Data("""
        {"id":"li-2","libraryId":"lib-1","mediaType":"book",
         "media":{"metadata":{"title":"T","authorName":"   ","seriesName":"  "}}}
        """.utf8)
        let item = try ABSJSON.decoder.decode(ABSLibraryItem.self, from: json)
        try await store.upsertItems(serverID: serverID, items: [item])

        let summary = try #require(try await store.item(serverID: serverID, itemID: "li-2"))
        #expect(summary.author == nil)
        #expect(summary.seriesName == nil)
    }
}

@Suite("Library payload decoding")
struct LibraryDecodingTests {
    @Test("Decodes the libraries wrapper object")
    func libraries() throws {
        let json = Data("""
        {"libraries":[{"id":"lib-1","name":"Audiobooks","mediaType":"book","icon":"audiobookshelf","displayOrder":1}]}
        """.utf8)
        let decoded = try ABSJSON.decoder.decode(ABSLibrariesResponse.self, from: json)
        #expect(decoded.libraries.first?.name == "Audiobooks")
        #expect(decoded.libraries.first?.isPodcast == false)
    }

    @Test("Decodes a minified item, including epoch-millisecond dates")
    func minifiedItem() throws {
        let json = Data("""
        {"id":"li-1","libraryId":"lib-1","mediaType":"book","addedAt":1600000000000,
         "updatedAt":1600000001000,"isMissing":false,"isInvalid":false,"numFiles":3,"size":512,
         "media":{"id":"bk-1","coverPath":"/metadata/x.jpg","tags":[],"numTracks":9,
         "numAudioFiles":9,"numChapters":12,"duration":3600.5,"size":512,"ebookFormat":"epub",
         "metadata":{"title":"The Hobbit","titleIgnorePrefix":"Hobbit, The","authorName":"Tolkien",
         "narratorName":"Rob Inglis","seriesName":"Middle-earth #1","genres":["Fantasy"],
         "publishedYear":"1937","explicit":false}}}
        """.utf8)
        let item = try ABSJSON.decoder.decode(ABSLibraryItem.self, from: json)

        #expect(item.media?.metadata.title == "The Hobbit")
        #expect(item.media?.metadata.narratorName == "Rob Inglis")
        #expect(item.media?.duration == 3600.5)
        #expect(item.hasAudio)
        #expect(item.hasEbook)
        #expect(item.addedAt == Date(timeIntervalSince1970: 1_600_000_000))
    }

    @Test("A library of loose files with almost no metadata still decodes")
    func sparseItem() throws {
        let json = Data("""
        {"id":"li-2","mediaType":"book","media":{"metadata":{}}}
        """.utf8)
        let item = try ABSJSON.decoder.decode(ABSLibraryItem.self, from: json)
        #expect(item.media?.metadata.title == nil)
        #expect(!item.hasAudio)
    }

    @Test("A page without `total` decodes, because collapsed series omit it")
    func pageWithoutTotal() throws {
        let json = Data("""
        {"results":[],"limit":100,"page":0}
        """.utf8)
        let page = try ABSJSON.decoder.decode(ABSLibraryItemsPage.self, from: json)
        #expect(page.total == nil)
        #expect(page.results.isEmpty)
    }

    @Test("Progress decodes, and a null finishedAt is not an error")
    func progress() throws {
        let json = Data("""
        {"id":"mp-1","libraryItemId":"li-1","episodeId":null,"mediaItemId":"bk-1",
         "mediaItemType":"book","duration":3600,"progress":0.25,"currentTime":900,
         "isFinished":false,"hideFromContinueListening":false,"ebookLocation":"",
         "ebookProgress":0,"lastUpdate":1700000000000,"startedAt":1699000000000,"finishedAt":null}
        """.utf8)
        let progress = try ABSJSON.decoder.decode(ABSMediaProgress.self, from: json)
        #expect(progress.libraryItemId == "li-1")
        #expect(progress.progress == 0.25)
        #expect(progress.finishedAt == nil)
        #expect(progress.lastUpdate == Date(timeIntervalSince1970: 1_700_000_000))
    }
}

@Suite("Duration formatting")
struct DurationFormattingTests {
    @Test("Hours and minutes for anything of real length")
    func hoursAndMinutes() {
        #expect(Format.duration(45_600) == "12h 40m")
        #expect(Format.duration(2_880) == "48m")
        #expect(Format.duration(7_200) == "2h")
    }

    @Test("A short chapter reads in seconds instead of rounding to nothing")
    func subMinuteReadsInSeconds() {
        // An eight-second credits chapter used to render as "0m".
        #expect(Format.duration(8) == "8s")
        #expect(Format.duration(45) == "45s")
        #expect(Format.duration(59) == "59s")
        #expect(Format.duration(60) == "1m")
    }

    @Test("Nothing at all is an em dash, not a zero")
    func absentDuration() {
        #expect(Format.duration(0) == "—")
        #expect(Format.duration(-5) == "—")
    }
}
