import Foundation

/// What a converter produces.
public enum ConversionTarget: String, Sendable, Hashable, Codable {
    /// MOBI or AZW3 in, EPUB out. Phase 13.
    case epub
    /// CBZ or CBR in, PDF out, for export. Phase 12.
    case pdf
}

public enum ConversionProgress: Sendable, Hashable {
    case parsing
    /// 0...1
    case writing(fraction: Double)
    case validating
    case finished(URL)
}

/// The converter seam. Phases 12 and 13 implement it; the reader only knows
/// that something can turn a file it cannot read into one it can.
public protocol FileConverting: Sendable {
    func convert(fileAt url: URL, to target: ConversionTarget) async throws -> URL
}

public enum ConversionError: Error, Sendable, Equatable {
    /// Surfaced to the user as "This file is DRM-protected and can't be opened."
    case drmProtected
    case parseFailed(stage: String)
    case outputInvalid(reason: String)
    case cancelled
}
