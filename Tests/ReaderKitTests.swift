import Foundation
import Testing
@testable import ReaderKit

/// Builds a byte header that looks like the real thing to the detector.
private enum Header {
    static func zip(firstEntryName: String = "page01.jpg") -> Data {
        var bytes = [UInt8]([0x50, 0x4B, 0x03, 0x04])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 26)) // rest of the local file header
        bytes.append(contentsOf: Array(firstEntryName.utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 64))
        return Data(bytes)
    }

    /// An EPUB is a ZIP whose first entry is `mimetype` + `application/epub+zip`.
    static func epub() -> Data {
        var bytes = [UInt8]([0x50, 0x4B, 0x03, 0x04])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 26))
        bytes.append(contentsOf: Array("mimetype".utf8))
        bytes.append(contentsOf: Array("application/epub+zip".utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 64))
        return Data(bytes)
    }

    static func pdf() -> Data { Data("%PDF-1.7\n%âãÏÓ".utf8) }

    static func rar4() -> Data {
        Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00] + [UInt8](repeating: 0, count: 64))
    }

    static func rar5() -> Data {
        Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00] + [UInt8](repeating: 0, count: 64))
    }

    /// PalmDB: `BOOKMOBI` sits at offset 60.
    static func palmDB() -> Data {
        var bytes = [UInt8](repeating: 0x41, count: 60)
        bytes.append(contentsOf: Array("BOOKMOBI".utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 60))
        return Data(bytes)
    }
}

@Suite("Ebook format detection")
struct EbookFormatDetectorTests {
    @Test("Recognises formats from their magic bytes")
    func magicBytes() {
        #expect(EbookFormatDetector.format(forHeader: Header.pdf()) == .pdf)
        #expect(EbookFormatDetector.format(forHeader: Header.epub()) == .epub)
        #expect(EbookFormatDetector.format(forHeader: Header.rar4()) == .cbr)
        #expect(EbookFormatDetector.format(forHeader: Header.rar5()) == .cbr)
        #expect(EbookFormatDetector.format(forHeader: Header.palmDB()) == .mobi)
    }

    @Test("A plain ZIP is ambiguous, and says so instead of guessing")
    func ambiguousZip() {
        #expect(EbookFormatDetector.format(forHeader: Header.zip()) == nil)
        #expect(EbookFormatDetector.detect(filename: "comic.cbz", header: Header.zip()) == .cbz)
        #expect(EbookFormatDetector.detect(filename: "book.epub", header: Header.zip()) == .epub)
    }

    @Test("Magic bytes beat a wrong extension")
    func bytesBeatExtension() {
        // A RAR named .cbz is common in the wild.
        #expect(EbookFormatDetector.detect(filename: "volume01.cbz", header: Header.rar4()) == .cbr)
        // A real EPUB named .cbz is still an EPUB.
        #expect(EbookFormatDetector.detect(filename: "mislabelled.cbz", header: Header.epub()) == .epub)
        #expect(EbookFormatDetector.detect(filename: "notes.epub", header: Header.pdf()) == .pdf)
    }

    @Test("MOBI and AZW3 share a container, so the name breaks the tie")
    func mobiVersusAzw3() {
        #expect(EbookFormatDetector.detect(filename: "book.mobi", header: Header.palmDB()) == .mobi)
        #expect(EbookFormatDetector.detect(filename: "book.azw3", header: Header.palmDB()) == .azw3)
        #expect(EbookFormatDetector.detect(filename: "book.azw", header: Header.palmDB()) == .mobi)
        #expect(EbookFormatDetector.detect(filename: nil, header: Header.palmDB()) == .mobi)
    }

    @Test("Falls back to the extension when the bytes say nothing")
    func unknownBytes() {
        let noise = Data([UInt8](repeating: 0x7F, count: 128))
        #expect(EbookFormatDetector.detect(filename: "book.epub", header: noise) == .epub)
        #expect(EbookFormatDetector.detect(filename: "book.unknown", header: noise) == nil)
        #expect(EbookFormatDetector.detect(filename: nil, header: Data()) == nil)
    }

    @Test("Extensions map the way ABS libraries are actually named")
    func extensions() {
        #expect(EbookFormatDetector.format(forFileExtension: "EPUB") == .epub)
        #expect(EbookFormatDetector.format(forFileExtension: ".pdf") == .pdf)
        #expect(EbookFormatDetector.format(forFileExtension: "kf8") == .azw3)
        #expect(EbookFormatDetector.format(forFileExtension: "prc") == .mobi)
        #expect(EbookFormatDetector.format(forFileExtension: "txt") == nil)
    }

    @Test("Reads only the header from disk, not the whole file")
    func readsFromDisk() throws {
        let url = URL.temporaryDirectory.appending(path: "detector-\(UUID().uuidString).bin")
        var contents = Header.epub()
        contents.append(Data(repeating: 0xAB, count: 2_000_000)) // 2 MB of body
        try contents.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try EbookFormatDetector.detect(fileAt: url) == .epub)
    }

    @Test("Routes each format to the right viewer")
    func routing() {
        #expect(EbookFormat.epub.backend == .readium)
        #expect(EbookFormat.pdf.backend == .pdfKit)
        #expect(EbookFormat.cbz.backend == .comicPager)
        #expect(EbookFormat.cbr.backend == .comicPager)
        #expect(EbookFormat.mobi.backend == .convertThenReadium)
        #expect(EbookFormat.azw3.requiresConversion)
        #expect(!EbookFormat.epub.requiresConversion)
    }

    @Test("Knows what Kindle accepts, so the button can be greyed out")
    func kindleFormats() {
        #expect(EbookFormat.epub.isAcceptedByKindle)
        #expect(EbookFormat.pdf.isAcceptedByKindle)
        #expect(!EbookFormat.cbz.isAcceptedByKindle)
        #expect(!EbookFormat.mobi.isAcceptedByKindle)
    }

    @Test("An unreadable format is an error the reader can show")
    func routerThrows() throws {
        let url = URL.temporaryDirectory.appending(path: "junk-\(UUID().uuidString).xyz")
        try Data([0x00, 0x01, 0x02]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ReaderError.unsupportedFormat(fileExtension: "xyz")) {
            try FormatRouter().backend(forFileAt: url)
        }
    }
}
