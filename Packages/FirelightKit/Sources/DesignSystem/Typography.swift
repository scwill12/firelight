import SwiftUI

/// Type tokens.
///
/// Every font here is derived from a system text style, so Dynamic Type works
/// up to the largest accessibility size without any call site opting in. A
/// fixed point size is never correct in Firelight.
///
/// Titles are serif: this is an app about books, and the serif is what makes a
/// shelf of covers read as a library rather than a file list.
public enum Typography {
    public static let screenTitle = Font.system(.largeTitle, design: .serif, weight: .semibold)
    public static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    public static let itemTitle = Font.system(.headline, design: .serif)
    /// The title on a detail screen. Big enough to lead the page, small enough
    /// that the cover, the author and the Play button all fit above the fold.
    public static let detailTitle = Font.system(.title3, design: .serif, weight: .semibold)
    public static let itemSubtitle = Font.system(.subheadline, design: .default)
    public static let body = Font.system(.body)
    public static let emphasisedBody = Font.system(.body, weight: .semibold)
    public static let caption = Font.system(.caption)
    /// Elapsed and remaining time *while it is running*, where digits must not
    /// shift as they change. Monospaced digits only — the rest of the face is
    /// the normal one, so a timecode still looks like the app around it.
    public static let timecode = Font.system(.footnote).monospacedDigit()
    /// A length read once, like "22h 30m left" on a shelf. Proportional: there
    /// is nothing here to jitter, and monospacing it made a library screen
    /// look like a terminal.
    public static let duration = Font.system(.footnote, weight: .medium)
}
