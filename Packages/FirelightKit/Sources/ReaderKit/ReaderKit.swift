import Foundation

/// Opens a file with the right viewer.
///
/// Phase 6 implements the EPUB and PDF backends; Phase 12 adds the comic pager
/// and Phase 13 the conversion step. The routing decision lives in
/// `EbookFormatDetector` so it can be tested without a reader.
public protocol FormatRouting: Sendable {
    func backend(forFileAt url: URL) throws -> ReaderBackend
}

public struct FormatRouter: FormatRouting {
    public init() {}

    public func backend(forFileAt url: URL) throws -> ReaderBackend {
        guard let format = try EbookFormatDetector.detect(fileAt: url) else {
            throw ReaderError.unsupportedFormat(fileExtension: url.pathExtension)
        }
        return format.backend
    }
}

public enum ReaderError: Error, Sendable, Equatable {
    case unsupportedFormat(fileExtension: String)
    case fileUnreadable
    /// Shown verbatim to the user as "This file is DRM-protected and can't be
    /// opened." Detected during conversion in Phase 13.
    case drmProtected
}
