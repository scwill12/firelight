import Foundation

/// Where the reader is in an ebook, in the form ABS stores.
///
/// ABS keeps `ebookLocation` as an opaque string and `ebookProgress` as a
/// fraction. The spec is explicit about what goes in the string: a Readium
/// locator for EPUB, a page number for PDF and comics. Keeping both shapes in
/// one type means the sync engine never has to care which it is holding.
public enum EbookPosition: Sendable, Hashable {
    /// A Readium locator, as its own JSON.
    case locator(json: String, progression: Double)
    /// A page, one-based, as PDFs and comics are numbered for people.
    case page(number: Int, of: Int?)

    /// What goes in `ebookLocation`.
    public var absLocation: String {
        switch self {
        case .locator(let json, _):
            return json
        case .page(let number, _):
            // A bare number is what a PDF reader on another device can read
            // back; wrapping it in JSON would make it unreadable to them.
            return String(number)
        }
    }

    /// What goes in `ebookProgress`, 0...1.
    public var absProgress: Double {
        switch self {
        case .locator(_, let progression):
            return min(max(progression, 0), 1)
        case .page(let number, let total):
            guard let total, total > 0 else { return 0 }
            return min(max(Double(number) / Double(total), 0), 1)
        }
    }

    /// Reads back whatever was stored, for either kind of book.
    public static func parse(location: String?, progress: Double?, totalPages: Int? = nil) -> EbookPosition? {
        guard let location, !location.isEmpty else {
            guard let progress, progress > 0 else { return nil }
            return .locator(json: "", progression: progress)
        }

        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare integer is a page number; anything else is a locator.
        if let page = Int(trimmed), !trimmed.contains("{") {
            return .page(number: page, of: totalPages)
        }
        return .locator(json: trimmed, progression: progress ?? 0)
    }

    public var pageNumber: Int? {
        if case .page(let number, _) = self { return number }
        return nil
    }

    public var locatorJSON: String? {
        if case .locator(let json, _) = self, !json.isEmpty { return json }
        return nil
    }
}
