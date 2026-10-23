import ABSKit
import Foundation
import Observation
import ConversionKit
import Persistence
import ReaderKit
import ReadiumShared
import SwiftUI

/// Drives reading: opening a book, where you are in it, and what you marked.
@MainActor
@Observable
public final class ReaderController {
    public enum Content {
        case none
        case epub(Publication)
        case pdf(URL)
        case comic(URL)
        case unsupported(String)
        /// Being turned into an EPUB right now.
        case converting(ConversionProgress)
    }

    public private(set) var content: Content = .none
    public private(set) var isOpening = false
    public private(set) var failure: String?
    public private(set) var highlights: [Highlight] = []

    public var itemID: String?
    public var title = ""
    public var author: String?

    /// Page number for a PDF; Readium handles its own for EPUB.
    public var currentPage = 1
    public var pageCount = 0
    /// 0...1 through the book.
    public private(set) var progression: Double = 0
    public private(set) var currentLocatorJSON: String?
    public private(set) var chapterTitle: String?

    public var settings: ReaderSettings {
        didSet { settings.save(to: .standard) }
    }

    /// Words in the book, estimated for the time-left figure.
    public private(set) var estimatedWords: Int = 0
    public private(set) var wordsPerMinute: Double?

    @ObservationIgnored private let highlightStore: HighlightStore?
    @ObservationIgnored private let session: SessionController
    @ObservationIgnored private let sync: ProgressSyncServiceBridge
    @ObservationIgnored private let speedEstimator = ReadingSpeedEstimator()
    @ObservationIgnored private var speedSamples: [ReadingSpeedEstimator.Sample] = []

    /// Narrow seam onto the sync service, so ReaderKit need not know about it.
    public struct ProgressSyncServiceBridge {
        public let record: @MainActor (_ itemID: String, _ location: String?, _ progress: Double) async -> Void
        public let latest: @MainActor (_ itemID: String) async -> (location: String?, progress: Double?)?

        public init(
            record: @escaping @MainActor (String, String?, Double) async -> Void,
            latest: @escaping @MainActor (String) async -> (location: String?, progress: Double?)?
        ) {
            self.record = record
            self.latest = latest
        }
    }

    public init(
        session: SessionController,
        persistence: PersistenceController?,
        sync: ProgressSyncServiceBridge
    ) {
        self.session = session
        self.sync = sync
        self.highlightStore = persistence.map { HighlightStore(modelContainer: $0.container) }
        self.settings = ReaderSettings.load(from: .standard)
    }

    private var serverID: UUID? { session.activeServer?.id }

    // MARK: - Opening

    public func open(item: LibraryItemSummary) async {
        itemID = item.id
        title = item.title
        author = item.author
        failure = nil
        isOpening = true
        content = .none
        defer { isOpening = false }

        guard let client = session.client() else {
            failure = L("Not connected to a server.")
            return
        }
        guard let format = item.ebookFormat.flatMap(EbookFormatDetector.format(forFileExtension:)) else {
            content = .unsupported(item.ebookFormat ?? "")
            return
        }

        do {
            let destination = try Self.cacheURL(itemID: item.id, format: format)
            let fileURL: URL
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                fileURL = destination
            } else {
                fileURL = try await client.downloadEbook(itemID: item.id, to: destination)
            }

            // Trust the bytes, not the extension: a mislabelled file is common.
            let detected = (try? EbookFormatDetector.detect(fileAt: fileURL)) ?? format
            switch detected.backend {
            case .pdfKit:
                content = .pdf(fileURL)
            case .readium:
                content = .epub(try await EPUBPublicationOpener.open(fileURL: fileURL))
            case .comicPager:
                content = .comic(fileURL)
            case .convertThenReadium:
                // MOBI and AZW3 become an EPUB once, then read like any other.
                content = .converting(.parsing)
                let converted = try await MOBIConverter().convertToEPUB(fileAt: fileURL) { progress in
                    self.content = .converting(progress)
                }
                content = .epub(try await EPUBPublicationOpener.open(fileURL: converted))
            }

            estimatedWords = Self.estimateWords(for: item)
            await restorePosition(itemID: item.id)
            await loadHighlights(itemID: item.id)
        } catch ConversionError.drmProtected {
            // The exact wording the spec asks for.
            failure = L("This file is DRM-protected and can't be opened.")
            content = .none
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? L("Couldn't open this book.")
            content = .none
        }
    }

    public func close() async {
        await saveProgress(force: true)
        content = .none
        itemID = nil
        speedSamples = []
    }

    // MARK: - Position

    private func restorePosition(itemID: String) async {
        guard let stored = await sync.latest(itemID) else { return }
        guard let position = EbookPosition.parse(
            location: stored.location,
            progress: stored.progress,
            totalPages: pageCount > 0 ? pageCount : nil
        ) else { return }

        switch position {
        case .page(let number, _):
            currentPage = max(1, number)
        case .locator(let json, let fraction):
            currentLocatorJSON = json.isEmpty ? nil : json
            progression = fraction
        }
    }

    /// Readium reported a new location.
    public func locationChanged(locator: Locator) {
        let fraction = locator.locations.totalProgression ?? progression
        progression = fraction
        chapterTitle = locator.title
        currentLocatorJSON = Self.json(from: locator)
        noteSpeedSample(fraction)
        Task { await saveProgress() }
    }

    /// PDFKit moved to a new page.
    public func pageChanged(to page: Int) {
        currentPage = page
        guard pageCount > 0 else { return }
        progression = min(max(Double(page) / Double(pageCount), 0), 1)
        noteSpeedSample(progression)
        Task { await saveProgress() }
    }

    private func noteSpeedSample(_ fraction: Double) {
        speedSamples.append(ReadingSpeedEstimator.Sample(fraction: fraction, at: .now))
        if speedSamples.count > 200 { speedSamples.removeFirst(speedSamples.count - 200) }
        wordsPerMinute = speedEstimator.wordsPerMinute(from: speedSamples, totalWords: estimatedWords)
    }

    /// Seconds left in the book, or nil until the reader's pace is known.
    public var timeRemaining: TimeInterval? {
        speedEstimator.timeRemaining(
            fraction: progression,
            totalWords: estimatedWords,
            wordsPerMinute: wordsPerMinute
        )
    }

    @ObservationIgnored private var lastSavedAt: Date?

    public func saveProgress(force: Bool = false) async {
        guard let itemID else { return }
        let now = Date.now
        if !force, let lastSavedAt, now.timeIntervalSince(lastSavedAt) < 10 { return }
        lastSavedAt = now

        let position: EbookPosition = switch content {
        case .pdf: .page(number: currentPage, of: pageCount > 0 ? pageCount : nil)
        default: .locator(json: currentLocatorJSON ?? "", progression: progression)
        }
        await sync.record(itemID, position.absLocation, position.absProgress)
    }

    // MARK: - Highlights

    public func loadHighlights(itemID: String) async {
        guard let highlightStore, let serverID else { return }
        highlights = (try? await highlightStore.highlights(serverID: serverID, itemID: itemID)) ?? []
    }

    @discardableResult
    public func addHighlight(text: String, color: HighlightColor = .yellow, note: String? = nil) async -> Bool {
        guard let highlightStore, let serverID, let itemID,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        let highlight = Highlight(
            itemID: itemID,
            text: text,
            note: note,
            color: color,
            locatorJSON: currentLocatorJSON ?? String(currentPage),
            progression: progression,
            chapterTitle: chapterTitle
        )
        try? await highlightStore.add(highlight, serverID: serverID)
        await loadHighlights(itemID: itemID)
        return true
    }

    public func updateHighlight(id: UUID, note: String?, color: HighlightColor?) async {
        guard let highlightStore, let itemID else { return }
        try? await highlightStore.update(id: id, note: note, color: color)
        await loadHighlights(itemID: itemID)
    }

    public func removeHighlight(id: UUID) async {
        guard let highlightStore, let itemID else { return }
        try? await highlightStore.remove(id: id)
        await loadHighlights(itemID: itemID)
    }

    /// Writes the highlights out as Markdown and returns the file to share.
    public func exportHighlights() -> URL? {
        let markdown = HighlightMarkdownExporter.markdown(
            bookTitle: title,
            author: author,
            highlights: highlights
        )
        let filename = HighlightMarkdownExporter.filename(forBookTitle: title)
        let url = URL.temporaryDirectory.appending(path: filename)
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    static func cacheURL(itemID: String, format: EbookFormat) throws -> URL {
        let root = try AppGroup.downloadsURL().appending(path: "ebooks")
        return root.appending(path: "\(itemID).\(format.fileExtension)")
    }

    /// A rough word count, for the time-left figure.
    ///
    /// ABS does not report one. Where there is an audio duration, 150 words a
    /// minute of narration is a far better estimate than a guess from file
    /// size; otherwise it falls back to a typical novel.
    static func estimateWords(for item: LibraryItemSummary) -> Int {
        if item.duration > 0 {
            return Int(item.duration / 60 * 150)
        }
        return 90_000
    }

    /// Readium's own JSON form, which is what ABS stores in `ebookLocation`
    /// and what another Readium client can read back.
    static func json(from locator: Locator) -> String? {
        try? locator.jsonString()
    }
}
