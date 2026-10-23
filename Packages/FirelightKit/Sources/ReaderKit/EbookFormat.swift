import Foundation

/// Which viewer opens a file.
public enum ReaderBackend: String, Sendable, Hashable, Codable {
    case readium
    case pdfKit
    case comicPager
    /// Converted to EPUB on first open, then read with Readium.
    case convertThenReadium
}

/// Every ebook format Firelight opens.
public enum EbookFormat: String, Sendable, Hashable, Codable, CaseIterable {
    case epub
    case pdf
    case cbz
    case cbr
    case mobi
    case azw3

    public var backend: ReaderBackend {
        switch self {
        case .epub: .readium
        case .pdf: .pdfKit
        // Both comic formats use Firelight's own pager: Readium's navigator
        // adds nothing for a bag of images, and one pager means CBZ and CBR
        // behave identically.
        case .cbz: .comicPager
        case .cbr: .comicPager
        case .mobi, .azw3: .convertThenReadium
        }
    }

    public var requiresConversion: Bool { backend == .convertThenReadium }

    public var isComic: Bool { self == .cbz || self == .cbr }

    /// Formats Amazon's Send to Kindle service accepts.
    public var isAcceptedByKindle: Bool {
        switch self {
        case .epub, .pdf: true
        case .cbz, .cbr, .mobi, .azw3: false
        }
    }

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .cbz: "CBZ"
        case .cbr: "CBR"
        case .mobi: "MOBI"
        case .azw3: "AZW3"
        }
    }
}

/// Identifies a file's format from its name and its first bytes.
///
/// A filename alone is not enough — ABS serves ebook files by id, and plenty of
/// libraries contain a `.cbz` that is really a RAR or an `.epub` with the wrong
/// extension. Magic bytes decide wherever they can; the extension only breaks
/// ties the bytes genuinely cannot (EPUB vs CBZ are both ZIP, MOBI vs AZW3 are
/// both PalmDB).
public enum EbookFormatDetector {
    /// The number of bytes `detect` needs. Read only this much of a large file.
    public static let headerLength = 128

    public static func format(forFileExtension fileExtension: String) -> EbookFormat? {
        switch fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "epub": .epub
        case "pdf": .pdf
        case "cbz", "zip": .cbz
        case "cbr", "rar": .cbr
        case "mobi", "prc", "azw": .mobi
        case "azw3", "kf8": .azw3
        default: nil
        }
    }

    /// What the bytes say, independent of any filename. Returns `nil` when the
    /// container is recognised but ambiguous (a plain ZIP), so the caller can
    /// fall back to the extension.
    public static func format(forHeader header: Data) -> EbookFormat? {
        if header.starts(with: Array("%PDF".utf8)) { return .pdf }
        if isRAR(header) { return .cbr }
        if isPalmDB(header) { return .mobi }
        if isZIP(header) {
            return isEPUB(header) ? .epub : nil
        }
        return nil
    }

    /// The detector the format router actually calls.
    public static func detect(filename: String?, header: Data) -> EbookFormat? {
        let byExtension = filename
            .map { URL(fileURLWithPath: $0).pathExtension }
            .flatMap(format(forFileExtension:))

        guard let byHeader = format(forHeader: header) else {
            // Unrecognised or ambiguous bytes: trust the extension.
            return byExtension
        }

        switch byHeader {
        case .cbr:
            // A RAR is a RAR whatever it is called.
            return .cbr
        case .mobi:
            // PalmDB covers MOBI, AZW and AZW3 alike; only the name tells them
            // apart without parsing the MOBI header's file version.
            return byExtension == .azw3 ? .azw3 : .mobi
        case .epub:
            // A real EPUB mimetype entry outranks a `.cbz` extension.
            return .epub
        case .pdf:
            return .pdf
        case .cbz, .azw3:
            return byHeader
        }
    }

    /// Reads just the header from disk, never the whole file.
    public static func detect(fileAt url: URL) throws -> EbookFormat? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: headerLength) ?? Data()
        return detect(filename: url.lastPathComponent, header: header)
    }

    // MARK: - Signatures

    static func isZIP(_ header: Data) -> Bool {
        let signatures = [
            Array<UInt8>([0x50, 0x4B, 0x03, 0x04]), // normal
            Array<UInt8>([0x50, 0x4B, 0x05, 0x06]), // empty archive
            Array<UInt8>([0x50, 0x4B, 0x07, 0x08]), // spanned
        ]
        return signatures.contains { header.starts(with: $0) }
    }

    /// An EPUB is a ZIP whose first entry is an uncompressed `mimetype` file
    /// containing `application/epub+zip`, which the spec puts at a fixed offset.
    static func isEPUB(_ header: Data) -> Bool {
        guard header.count >= 58 else { return false }
        let bytes = [UInt8](header)
        let nameRange = 30..<38
        let valueRange = 38..<58
        guard String(decoding: bytes[nameRange], as: UTF8.self) == "mimetype" else { return false }
        return String(decoding: bytes[valueRange], as: UTF8.self) == "application/epub+zip"
    }

    static func isRAR(_ header: Data) -> Bool {
        let v4 = Array<UInt8>([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])
        let v5 = Array<UInt8>([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
        return header.starts(with: v4) || header.starts(with: v5)
    }

    /// MOBI, AZW and AZW3 are all PalmDB files whose type/creator at offset 60
    /// is `BOOKMOBI`.
    static func isPalmDB(_ header: Data) -> Bool {
        guard header.count >= 68 else { return false }
        let bytes = [UInt8](header)
        return String(decoding: bytes[60..<68], as: UTF8.self) == "BOOKMOBI"
    }
}
