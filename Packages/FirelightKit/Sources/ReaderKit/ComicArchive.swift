import Foundation
import ReadiumShared
import ReadiumStreamer
import UIKit
import Unrar

/// Reads the pages out of a comic archive.
///
/// Uses Readium's own archive layer rather than adding a ZIP dependency: the
/// upstream ZIPFoundation and Readium's fork share a package identity, so
/// SwiftPM refuses to resolve both. Readium opens the archive it already
/// knows how to open, and this just picks the images out in the right order.
/// `@unchecked` because Readium's `Container` is not annotated `Sendable`.
/// The archive is opened and read from the reader's own context and never
/// handed between tasks; marking it here is narrower than making every call
/// site deal with it.
public struct ComicArchive: @unchecked Sendable {
    /// One page, as a path inside the archive.
    public struct Page: Sendable, Hashable, Identifiable {
        public let index: Int
        public let path: String
        public var id: Int { index }
    }

    /// Where the pages come from. CBZ and CBR differ only here.
    private enum Backing {
        case zip(Container)
        case rar(Archive)
    }

    public let pages: [Page]
    private let backing: Backing

    private init(pages: [Page], backing: Backing) {
        self.pages = pages
        self.backing = backing
    }

    public var pageCount: Int { pages.count }

    /// Opens a comic, whichever container it is in.
    ///
    /// The format is decided by the file's bytes, not its extension: a `.cbz`
    /// that is really a RAR is common enough to be the rule rather than the
    /// exception.
    public static func open(fileURL: URL) async throws -> ComicArchive {
        let format = (try? EbookFormatDetector.detect(fileAt: fileURL)) ?? .cbz
        return switch format {
        case .cbr: try openRAR(fileURL: fileURL)
        default: try await openZIP(fileURL: fileURL)
        }
    }

    private static func openZIP(fileURL: URL) async throws -> ComicArchive {
        guard let url = FileURL(url: fileURL) else { throw ReaderError.fileUnreadable }

        let retriever = AssetRetriever(httpClient: DefaultHTTPClient())
        let asset = try await retriever.retrieve(url: url).get()
        guard case .container(let containerAsset) = asset else {
            throw ReaderError.unsupportedFormat(fileExtension: fileURL.pathExtension)
        }

        let ordered = orderedImagePaths(from: containerAsset.container.entries.map(\.string))
        guard !ordered.isEmpty else { throw ReaderError.fileUnreadable }

        return ComicArchive(
            pages: ordered.enumerated().map { Page(index: $0.offset, path: $0.element) },
            backing: .zip(containerAsset.container)
        )
    }

    private static func openRAR(fileURL: URL) throws -> ComicArchive {
        let archive: Archive
        do {
            archive = try Archive(fileURL: fileURL)
        } catch {
            throw ReaderError.fileUnreadable
        }

        // An encrypted comic is a real thing and cannot be read without a
        // password, which Firelight does not ask for.
        let entries = (try? archive.entries()) ?? []
        let ordered = orderedImagePaths(from: entries.map(\.fileName))
        guard !ordered.isEmpty else { throw ReaderError.fileUnreadable }

        return ComicArchive(
            pages: ordered.enumerated().map { Page(index: $0.offset, path: $0.element) },
            backing: .rar(archive)
        )
    }

    /// Loads one page's image.
    public func image(at index: Int) async -> UIImage? {
        guard pages.indices.contains(index) else { return nil }
        let path = pages[index].path

        switch backing {
        case .zip(let container):
            guard let url = AnyURL(string: path),
                  let resource = container[url],
                  let data = try? await resource.read().get()
            else { return nil }
            return UIImage(data: data)

        case .rar(let archive):
            guard let entry = (try? archive.entries())?.first(where: { $0.fileName == path }),
                  let data = try? archive.extract(entry)
            else { return nil }
            return UIImage(data: data)
        }
    }

    public func close() {
        if case .zip(let container) = backing { container.close() }
    }

    // MARK: - Ordering

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "avif"]

    /// Images only, in the order a reader expects.
    ///
    /// Comic archives are a mess: macOS resource forks, hidden files, and
    /// filenames that sort wrongly as plain strings ("page10" before "page9").
    /// A natural, case-insensitive comparison is the only ordering that
    /// matches what a human sees in the folder.
    public static func orderedImagePaths(from paths: [String]) -> [String] {
        paths
            .filter { path in
                let name = (path as NSString).lastPathComponent
                guard !name.hasPrefix("."), !path.contains("__MACOSX/") else { return false }
                return imageExtensions.contains((path as NSString).pathExtension.lowercased())
            }
            .sorted { naturalCompare($0, $1) }
    }

    /// Compares two names the way a person reads them: digit runs as numbers.
    static func naturalCompare(_ first: String, _ second: String) -> Bool {
        first.compare(
            second,
            options: [.numeric, .caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: nil
        ) == .orderedAscending
    }
}

/// Turns a comic into a PDF for export.
public enum ComicPDFExporter {
    /// Renders every page onto its own PDF page, sized to the image.
    ///
    /// Each page keeps its own dimensions rather than being forced onto a
    /// fixed sheet: comic pages are not all the same shape, and a
    /// double-page spread letterboxed onto A4 looks broken.
    public static func pdf(from images: [UIImage], at destination: URL) throws -> URL {
        guard !images.isEmpty else { throw ReaderError.fileUnreadable }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: images[0].size))
        let data = renderer.pdfData { context in
            for image in images {
                let bounds = CGRect(origin: .zero, size: image.size)
                context.beginPage(withBounds: bounds, pageInfo: [:])
                image.draw(in: bounds)
            }
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return destination
    }
}
