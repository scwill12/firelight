import Foundation
import PDFKit
import Testing
import UIKit
@testable import ReaderKit

@Suite("Comic archive ordering")
struct ComicArchiveOrderingTests {
    @Test("Pages read in the order a person sees them, not ASCII order")
    func naturalOrdering() {
        // Plain string sorting puts page10 before page9, which silently
        // shuffles every comic with more than nine pages.
        let paths = ["page10.jpg", "page9.jpg", "page1.jpg", "page20.jpg", "page2.jpg"]
        #expect(ComicArchive.orderedImagePaths(from: paths) == [
            "page1.jpg", "page2.jpg", "page9.jpg", "page10.jpg", "page20.jpg",
        ])
    }

    @Test("Zero-padded names order correctly too")
    func paddedNames() {
        let paths = ["001.png", "010.png", "002.png"]
        #expect(ComicArchive.orderedImagePaths(from: paths) == ["001.png", "002.png", "010.png"])
    }

    @Test("Nested folders keep their order")
    func nestedFolders() {
        let paths = ["ch2/page1.jpg", "ch1/page2.jpg", "ch1/page1.jpg", "ch10/page1.jpg"]
        #expect(ComicArchive.orderedImagePaths(from: paths) == [
            "ch1/page1.jpg", "ch1/page2.jpg", "ch2/page1.jpg", "ch10/page1.jpg",
        ])
    }

    @Test("Non-images are left out")
    func filtersNonImages() {
        let paths = ["page1.jpg", "ComicInfo.xml", "readme.txt", "page2.png", "thumbs.db"]
        #expect(ComicArchive.orderedImagePaths(from: paths) == ["page1.jpg", "page2.png"])
    }

    @Test("macOS resource forks and hidden files are ignored")
    func ignoresJunk() {
        // Every archive made on a Mac carries these, and they are not pages.
        let paths = [
            "__MACOSX/._page1.jpg", "._page1.jpg", ".DS_Store",
            "page1.jpg", "page2.jpg",
        ]
        #expect(ComicArchive.orderedImagePaths(from: paths) == ["page1.jpg", "page2.jpg"])
    }

    @Test("Extensions are matched whatever their case")
    func caseInsensitiveExtensions() {
        let paths = ["PAGE1.JPG", "page2.JpEg", "page3.WEBP"]
        #expect(ComicArchive.orderedImagePaths(from: paths).count == 3)
    }

    @Test("An archive with no images yields nothing rather than an empty page")
    func noImages() {
        #expect(ComicArchive.orderedImagePaths(from: ["readme.txt", "ComicInfo.xml"]).isEmpty)
    }

    @Test("Mixed naming schemes still sort sensibly")
    func mixedNames() {
        let paths = ["cover.jpg", "page1.jpg", "page2.jpg"]
        let ordered = ComicArchive.orderedImagePaths(from: paths)
        // "cover" sorts before "page" alphabetically, which is also right.
        #expect(ordered.first == "cover.jpg")
        #expect(ordered.count == 3)
    }
}

@Suite("Comic PDF export")
struct ComicPDFExportTests {
    private func image(width: Int, height: Int, colour: UIColor) -> UIImage {
        let size = CGSize(width: width, height: height)
        return UIGraphicsImageRenderer(size: size).image { context in
            colour.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test("Every page lands in the PDF")
    func pageCount() throws {
        let images = [
            image(width: 100, height: 150, colour: .red),
            image(width: 100, height: 150, colour: .green),
            image(width: 100, height: 150, colour: .blue),
        ]
        let url = URL.temporaryDirectory.appending(path: "comic-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try ComicPDFExporter.pdf(from: images, at: url)
        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 3)
    }

    @Test("Each page keeps its own size, so a spread is not letterboxed")
    func mixedPageSizes() throws {
        let images = [
            image(width: 100, height: 150, colour: .red),
            image(width: 200, height: 150, colour: .green),   // a double-page spread
        ]
        let url = URL.temporaryDirectory.appending(path: "comic-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try ComicPDFExporter.pdf(from: images, at: url)
        let document = try #require(PDFDocument(url: url))
        let first = try #require(document.page(at: 0)).bounds(for: .mediaBox)
        let second = try #require(document.page(at: 1)).bounds(for: .mediaBox)
        #expect(first.width != second.width)
    }

    @Test("Exporting nothing is an error, not an empty file")
    func refusesEmpty() {
        let url = URL.temporaryDirectory.appending(path: "empty-\(UUID().uuidString).pdf")
        #expect(throws: ReaderError.self) {
            _ = try ComicPDFExporter.pdf(from: [], at: url)
        }
    }
}

@Suite("Comic archive reading")
struct ComicArchiveReadingTests {
    /// A real CBZ, committed as a fixture: three pages written out of order,
    /// with a macOS resource fork and a ComicInfo.xml alongside them.
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/sample.cbz")
    }

    @Test("Opens a real CBZ and finds its pages in reading order")
    func opensRealArchive() async throws {
        let archive = try await ComicArchive.open(fileURL: fixtureURL)
        defer { archive.close() }

        #expect(archive.pageCount == 3)
        #expect(archive.pages.map(\.path) == ["page1.png", "page2.png", "page10.png"])
    }

    @Test("Each page decodes to an image")
    func decodesPages() async throws {
        let archive = try await ComicArchive.open(fileURL: fixtureURL)
        defer { archive.close() }

        for index in 0..<archive.pageCount {
            let image = await archive.image(at: index)
            #expect(image != nil, "page \(index) did not decode")
            #expect(image?.size == CGSize(width: 4, height: 6))
        }
    }

    @Test("A page index outside the archive is nil, not a crash")
    func outOfRange() async throws {
        let archive = try await ComicArchive.open(fileURL: fixtureURL)
        defer { archive.close() }

        #expect(await archive.image(at: -1) == nil)
        #expect(await archive.image(at: 99) == nil)
    }

    @Test("A file that is not an archive is refused")
    func refusesNonArchive() async throws {
        let url = URL.temporaryDirectory.appending(path: "not-a-comic-\(UUID().uuidString).cbz")
        try Data("this is not a zip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: (any Error).self) {
            _ = try await ComicArchive.open(fileURL: url)
        }
    }

    @Test("A real CBZ round-trips into a PDF with the right page count")
    func exportsToPDF() async throws {
        let archive = try await ComicArchive.open(fileURL: fixtureURL)
        defer { archive.close() }

        var images: [UIImage] = []
        for index in 0..<archive.pageCount {
            if let image = await archive.image(at: index) { images.append(image) }
        }

        let url = URL.temporaryDirectory.appending(path: "export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try ComicPDFExporter.pdf(from: images, at: url)

        #expect(try #require(PDFDocument(url: url)).pageCount == 3)
    }
}
