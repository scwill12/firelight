import Foundation
import SwiftData
import Testing
@testable import Persistence
@testable import ReaderKit

@Suite("Reader settings")
struct ReaderSettingsTests {
    @Test("Out-of-range values are clamped, not accepted")
    func clamping() {
        let tiny = ReaderSettings(
            font: .literata, fontScale: 0.1, lineHeight: 0.2, margin: -10,
            isJustified: false, isHyphenated: true, theme: .sepia,
            pageTurn: .slide, allowsTwoColumns: true
        )
        #expect(tiny.fontScale == 0.5)
        #expect(tiny.lineHeight == 1.0)
        #expect(tiny.margin == 0)

        let huge = ReaderSettings(
            font: .literata, fontScale: 99, lineHeight: 99, margin: 999,
            isJustified: false, isHyphenated: true, theme: .sepia,
            pageTurn: .slide, allowsTwoColumns: true
        )
        #expect(huge.fontScale == 3.0)
        #expect(huge.lineHeight == 3.0)
        #expect(huge.margin == 80)
    }

    @Test("Adjusting the size stops at the ends")
    func adjustment() {
        var settings = ReaderSettings.default
        for _ in 0..<50 { settings.adjustFontScale(by: 0.1) }
        #expect(settings.fontScale == 3.0)
        for _ in 0..<100 { settings.adjustFontScale(by: -0.1) }
        #expect(settings.fontScale == 0.5)
    }

    @Test("Settings survive a round trip through defaults")
    func persistence() throws {
        let defaults = try #require(UserDefaults(suiteName: "firelight.tests.reader.\(UUID().uuidString)"))
        var settings = ReaderSettings.default
        settings.font = .openDyslexic
        settings.theme = .trueBlack
        settings.pageTurn = .scroll
        settings.save(to: defaults)

        let loaded = ReaderSettings.load(from: defaults)
        #expect(loaded.font == .openDyslexic)
        #expect(loaded.theme == .trueBlack)
        #expect(loaded.pageTurn == .scroll)
    }

    @Test("Nothing stored means the defaults, not a crash")
    func missingDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "firelight.tests.empty.\(UUID().uuidString)"))
        #expect(ReaderSettings.load(from: defaults) == .default)
    }

    @Test("Every fixed theme is readable, and system defers")
    func themes() {
        for theme in ReaderTheme.allCases where theme != .system {
            let colors = theme.colors
            #expect(colors != nil, "\(theme) must fix its colours")
        }
        #expect(ReaderTheme.system.colors == nil)
    }

    @Test("The publisher's own typeface is left alone")
    func publisherFont() {
        #expect(ReaderFont.publisher.familyName == nil)
        #expect(ReaderFont.openDyslexic.familyName == "OpenDyslexic")
    }
}

@Suite("Reading speed")
struct ReadingSpeedTests {
    private let estimator = ReadingSpeedEstimator()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func samples(_ pairs: [(Double, TimeInterval)]) -> [ReadingSpeedEstimator.Sample] {
        pairs.map { .init(fraction: $0.0, at: start.addingTimeInterval($0.1)) }
    }

    @Test("Too little evidence means no claim")
    func notEnoughSamples() {
        let result = estimator.wordsPerMinute(from: samples([(0.0, 0), (0.1, 60)]), totalWords: 90_000)
        #expect(result == nil)
    }

    @Test("A steady reader gets a sensible figure")
    func steadyReading() throws {
        // 1% of a 90,000-word book each minute = 900 words/min… too fast to be
        // plausible, so use a slower pace: 0.2% per minute = 180 wpm.
        let pairs = (0..<10).map { (Double($0) * 0.002, TimeInterval($0) * 60) }
        let speed = try #require(estimator.wordsPerMinute(from: samples(pairs), totalWords: 90_000))
        #expect(abs(speed - 180) < 1)
    }

    @Test("A long gap is the book being put down, not slow reading")
    func ignoresLongGaps() throws {
        let withGap = samples([
            (0.000, 0), (0.002, 60), (0.004, 120),
            (0.006, 86_400),            // picked up again a day later
            (0.008, 86_460), (0.010, 86_520),
        ])
        let speed = try #require(estimator.wordsPerMinute(from: withGap, totalWords: 90_000))
        // The day-long gap must not drag the figure to nearly zero.
        #expect(speed > 100)
    }

    @Test("Flipping backwards does not count as reading")
    func ignoresBackwards() throws {
        let pairs = samples([
            (0.000, 0), (0.002, 60), (0.001, 120), (0.003, 180), (0.005, 240),
        ])
        let speed = try #require(estimator.wordsPerMinute(from: pairs, totalWords: 90_000))
        #expect(speed > 0)
    }

    @Test("An implausible figure is discarded rather than shown")
    func rejectsImplausible() {
        // A whole book in two minutes.
        let pairs = samples([(0.0, 0), (0.3, 30), (0.6, 60), (1.0, 120)])
        #expect(estimator.wordsPerMinute(from: pairs, totalWords: 90_000) == nil)
    }

    @Test("Time left is proportional to what is unread")
    func timeRemaining() throws {
        let remaining = try #require(estimator.timeRemaining(
            fraction: 0.5, totalWords: 90_000, wordsPerMinute: 250
        ))
        // 45,000 words at 250 wpm = 180 minutes.
        #expect(abs(remaining - 180 * 60) < 1)
    }

    @Test("No speed means no estimate, rather than a made-up one")
    func noSpeedNoEstimate() {
        #expect(estimator.timeRemaining(fraction: 0.5, totalWords: 90_000, wordsPerMinute: nil) == nil)
    }
}

@Suite("Ebook position")
struct EbookPositionTests {
    @Test("A PDF stores a bare page number another reader can use")
    func pageEncoding() {
        let position = EbookPosition.page(number: 42, of: 200)
        #expect(position.absLocation == "42")
        #expect(abs(position.absProgress - 0.21) < 0.001)
    }

    @Test("An EPUB stores its Readium locator verbatim")
    func locatorEncoding() {
        let json = #"{"href":"ch3.xhtml","locations":{"totalProgression":0.42}}"#
        let position = EbookPosition.locator(json: json, progression: 0.42)
        #expect(position.absLocation == json)
        #expect(position.absProgress == 0.42)
    }

    @Test("Reading a stored position back tells the two apart")
    func parsing() {
        let page = EbookPosition.parse(location: "42", progress: 0.2, totalPages: 200)
        #expect(page?.pageNumber == 42)

        let locator = EbookPosition.parse(location: #"{"href":"ch1.xhtml"}"#, progress: 0.1)
        #expect(locator?.locatorJSON != nil)
        #expect(locator?.pageNumber == nil)
    }

    @Test("Progress with no location is still a position")
    func progressOnly() {
        let position = EbookPosition.parse(location: nil, progress: 0.33)
        #expect(position?.absProgress == 0.33)
    }

    @Test("Nothing stored is nothing, not zero")
    func empty() {
        #expect(EbookPosition.parse(location: nil, progress: nil) == nil)
        #expect(EbookPosition.parse(location: "", progress: 0) == nil)
    }

    @Test("A page with no known total reports no progress rather than a wrong one")
    func pageWithoutTotal() {
        #expect(EbookPosition.page(number: 10, of: nil).absProgress == 0)
    }
}

@Suite("Highlight export")
struct HighlightExportTests {
    private func highlight(
        _ text: String,
        note: String? = nil,
        progression: Double,
        chapter: String? = nil,
        color: HighlightColor = .yellow
    ) -> Highlight {
        Highlight(
            itemID: "li-1", text: text, note: note, color: color,
            locatorJSON: "{}", progression: progression, chapterTitle: chapter
        )
    }

    @Test("Produces Markdown another app can open")
    func markdown() {
        let output = HighlightMarkdownExporter.markdown(
            bookTitle: "The Hobbit",
            author: "J. R. R. Tolkien",
            highlights: [
                highlight("In a hole in the ground", progression: 0.01, chapter: "An Unexpected Party"),
                highlight("Roads go ever ever on", note: "Remember this", progression: 0.5, chapter: "Riddles"),
            ]
        )
        #expect(output.hasPrefix("# The Hobbit"))
        #expect(output.contains("*J. R. R. Tolkien*"))
        #expect(output.contains("## An Unexpected Party"))
        #expect(output.contains("> In a hole in the ground"))
        #expect(output.contains("**Note:** Remember this"))
    }

    @Test("Highlights come out in reading order, not entry order")
    func ordering() {
        let output = HighlightMarkdownExporter.markdown(
            bookTitle: "Book", author: nil,
            highlights: [
                highlight("Later", progression: 0.9),
                highlight("Earlier", progression: 0.1),
            ]
        )
        let earlier = try! #require(output.range(of: "Earlier"))
        let later = try! #require(output.range(of: "Later"))
        #expect(earlier.lowerBound < later.lowerBound)
    }

    @Test("A chapter heading appears once, not per highlight")
    func chapterHeadingsAreGrouped() {
        let output = HighlightMarkdownExporter.markdown(
            bookTitle: "Book", author: nil,
            highlights: [
                highlight("One", progression: 0.1, chapter: "Chapter One"),
                highlight("Two", progression: 0.2, chapter: "Chapter One"),
            ]
        )
        #expect(output.components(separatedBy: "## Chapter One").count - 1 == 1)
    }

    @Test("A multi-paragraph passage stays quoted throughout")
    func multilineQuoting() {
        let output = HighlightMarkdownExporter.markdown(
            bookTitle: "Book", author: nil,
            highlights: [highlight("First line\nSecond line", progression: 0.1)]
        )
        #expect(output.contains("> First line"))
        #expect(output.contains("> Second line"))
    }

    @Test("An empty export says so rather than producing a blank file")
    func noHighlights() {
        let output = HighlightMarkdownExporter.markdown(bookTitle: "Book", author: nil, highlights: [])
        #expect(output.contains("_No highlights yet._"))
    }

    @Test("Filenames survive a filesystem")
    func filenames() {
        #expect(HighlightMarkdownExporter.filename(forBookTitle: "The Hobbit") == "The Hobbit — Highlights.md")
        let awkward = HighlightMarkdownExporter.filename(forBookTitle: "Who? / What: Why*")
        #expect(!awkward.contains("/"))
        #expect(!awkward.contains(":"))
        #expect(HighlightMarkdownExporter.filename(forBookTitle: "///") == "Highlights — Highlights.md")
    }
}

@Suite("Highlight store")
struct HighlightStoreTests {
    private func makeStore() throws -> HighlightStore {
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
        return HighlightStore(modelContainer: container)
    }

    private let serverID = UUID()

    @Test("A highlight is kept, with its note and colour")
    func roundTrip() async throws {
        let store = try makeStore()
        let highlight = Highlight(
            itemID: "li-1", text: "A passage", note: "A note",
            color: .green, locatorJSON: "{}", progression: 0.3
        )
        try await store.add(highlight, serverID: serverID)

        let stored = try await store.highlights(serverID: serverID, itemID: "li-1")
        #expect(stored.count == 1)
        #expect(stored.first?.note == "A note")
        #expect(stored.first?.color == .green)
    }

    @Test("Highlights come back in reading order")
    func ordering() async throws {
        let store = try makeStore()
        for progression in [0.8, 0.2, 0.5] {
            try await store.add(
                Highlight(itemID: "li-1", text: "\(progression)", color: .yellow,
                          locatorJSON: "{}", progression: progression),
                serverID: serverID
            )
        }
        let stored = try await store.highlights(serverID: serverID, itemID: "li-1")
        #expect(stored.map(\.progression) == [0.2, 0.5, 0.8])
    }

    @Test("A note can be added later, and the colour changed")
    func update() async throws {
        let store = try makeStore()
        let highlight = Highlight(itemID: "li-1", text: "Text", color: .yellow, locatorJSON: "{}", progression: 0.1)
        try await store.add(highlight, serverID: serverID)
        try await store.update(id: highlight.id, note: "Added later", color: .pink)

        let stored = try await store.highlights(serverID: serverID, itemID: "li-1").first
        #expect(stored?.note == "Added later")
        #expect(stored?.color == .pink)
    }

    @Test("Clearing a note removes it rather than storing an empty one")
    func clearingNote() async throws {
        let store = try makeStore()
        let highlight = Highlight(itemID: "li-1", text: "Text", note: "A note",
                                  color: .yellow, locatorJSON: "{}", progression: 0.1)
        try await store.add(highlight, serverID: serverID)
        try await store.update(id: highlight.id, note: "", color: nil)
        #expect(try await store.highlights(serverID: serverID, itemID: "li-1").first?.note == nil)
    }

    @Test("Deleting removes it")
    func remove() async throws {
        let store = try makeStore()
        let highlight = Highlight(itemID: "li-1", text: "Text", color: .yellow, locatorJSON: "{}", progression: 0.1)
        try await store.add(highlight, serverID: serverID)
        try await store.remove(id: highlight.id)
        #expect(try await store.highlights(serverID: serverID, itemID: "li-1").isEmpty)
    }

    @Test("Books do not see each other's highlights")
    func separateBooks() async throws {
        let store = try makeStore()
        try await store.add(
            Highlight(itemID: "li-1", text: "One", color: .yellow, locatorJSON: "{}", progression: 0.1),
            serverID: serverID
        )
        try await store.add(
            Highlight(itemID: "li-2", text: "Two", color: .yellow, locatorJSON: "{}", progression: 0.1),
            serverID: serverID
        )
        #expect(try await store.highlights(serverID: serverID, itemID: "li-1").count == 1)
        #expect(try await store.allHighlights(serverID: serverID).count == 2)
    }
}
