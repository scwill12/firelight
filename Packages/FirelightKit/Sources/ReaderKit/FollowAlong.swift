import Foundation

/// Which e-reader the listener follows along on.
///
/// The device matters because they do not all count the same thing. A Kindle
/// counts *locations* — roughly 128 bytes of the source file — and only shows
/// page numbers when the publisher has supplied a mapping from a print
/// edition. Everything else counts pages, but a reflowable reader repaginates
/// when you change the font, so "page 150" on a Kobo at large type is not
/// page 150 on the same Kobo at small type.
///
/// Firelight therefore asks the reader what *their* copy says rather than
/// pretending there is one true page number.
public enum ReadingDevice: String, Codable, CaseIterable, Sendable, Identifiable {
    case kindle
    case kobo
    case nook
    case appleBooks
    case print

    public var id: String { rawValue }

    /// What this device counts in by default.
    public var defaultUnit: ReadingUnit {
        self == .kindle ? .location : .page
    }

    /// Whether the reader may sensibly choose between locations and pages.
    ///
    /// Only Kindle shows both, and only for books whose publisher provided
    /// print page numbers. The others have pages and nothing else.
    public var offersBothUnits: Bool {
        self == .kindle
    }
}

/// Which Kindle, for the sake of telling the listener where to look.
///
/// Worth being plain about what this does and does not do: a *location* is a
/// fixed slice of the book file, identical on every Kindle ever made, and a
/// Kindle page number comes from the publisher. So the model changes none of
/// the arithmetic. What it changes is the instructions, because where the
/// figure is shown differs between a button-less Paperwhite and the app.
public enum KindleModel: String, Codable, CaseIterable, Sendable, Identifiable {
    case kindle
    case paperwhite
    case colorsoft
    case oasis
    case scribe
    case app

    public var id: String { rawValue }

    /// Where that model shows the figure.
    public var whereToLook: String {
        switch self {
        case .kindle, .paperwhite, .colorsoft, .oasis:
            "Tap the top of the screen, then Go To. The last location is listed there; tapping the middle of a page shows where you are now."
        case .scribe:
            "Tap the top of the screen, then Go To. The Scribe lists the last location beside the page slider."
        case .app:
            "Tap the middle of the page, then the progress bar at the bottom. The Kindle app shows the location and the last one in the book."
        }
    }
}

/// What a reader's progress is measured in.
public enum ReadingUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Kindle locations. Start at 1 and have nothing to do with pages.
    case location
    /// Pages, as that device reports them at the reader's own font size.
    case page

    public var id: String { rawValue }
}

/// One listener's copy of one book.
///
/// Four numbers, and every one of them earns its place:
///
/// - `firstPosition` and `lastPosition` are what the listener's own reader
///   shows at the start and end of the text. Usually 1 and the last page, but
///   plenty of editions number their front matter, so chapter one opens on
///   page 12.
/// - `startProgress` and `endProgress` are where in the *audio* those two
///   points fall. They are 0 and 1 until the listener says otherwise, and
///   they are what makes a foreword survivable: an audiobook that opens with
///   eight minutes of publisher's note is eight minutes in which the printed
///   text has not started, and without saying so the estimate runs ahead for
///   the rest of the book.
public struct ReadingEdition: Sendable, Hashable, Codable {
    public var unit: ReadingUnit
    /// What the reader shows where the text begins.
    public var firstPosition: Int
    /// What the reader shows where the text ends.
    public var lastPosition: Int
    /// Where in the audio `firstPosition` begins, 0...1.
    public var startProgress: Double
    /// Where in the audio `lastPosition` ends, 0...1.
    public var endProgress: Double

    public init(
        unit: ReadingUnit,
        firstPosition: Int = 1,
        lastPosition: Int,
        startProgress: Double = 0,
        endProgress: Double = 1
    ) {
        self.unit = unit
        self.firstPosition = firstPosition
        self.lastPosition = lastPosition
        self.startProgress = startProgress
        self.endProgress = endProgress
    }

    /// An edition can only place a position when it runs forwards and has
    /// somewhere to run.
    public var isUsable: Bool {
        lastPosition > 0 && lastPosition >= firstPosition && firstPosition >= 1
    }

    /// True when the listener has calibrated either end against the audio.
    public var isCalibrated: Bool {
        let window = window
        return window.start > 0 || window.end < 1
    }

    /// The stretch of audio the printed text actually covers.
    ///
    /// Validated as a pair, not one end at a time: a start past its own end
    /// is not half-usable, it is nonsense, and honouring either half of it
    /// would place the reader somewhere worse than the plain estimate does.
    var window: (start: Double, end: Double) {
        guard startProgress.isFinite, endProgress.isFinite,
              startProgress >= 0, endProgress <= 1,
              endProgress - startProgress > 0.0001
        else { return (0, 1) }
        return (startProgress, endProgress)
    }

    var usableStart: Double { window.start }
    var usableEnd: Double { window.end }
}

/// Where in the printed text the listener probably is.
///
/// Deliberately an *estimate*, and named so. The map from audio time to text
/// is linear, which is the best any follow-along can do without a synchronised
/// text: narration speed varies, and an audiobook carries credits and a
/// publisher's note that the page count does not. Treat it as a landmark for
/// finding your place, not as a citation.
public struct FollowAlongPosition: Sendable, Hashable {
    public let value: Int
    public let total: Int
    public let unit: ReadingUnit

    public init(value: Int, total: Int, unit: ReadingUnit) {
        self.value = value
        self.total = total
        self.unit = unit
    }
}

public enum FollowAlong {
    /// Maps progress through the audiobook onto the listener's own edition.
    ///
    /// Returns nil rather than guessing when there is nothing to map onto —
    /// an edition with no length, or a book that has not started being
    /// measured. A nil here means "say nothing", never "say zero".
    public static func position(
        progress: Double,
        edition: ReadingEdition
    ) -> FollowAlongPosition? {
        guard edition.isUsable else { return nil }
        guard progress.isFinite else { return nil }

        let clamped = min(max(progress, 0), 1)
        let start = edition.usableStart
        let end = edition.usableEnd

        // Flat before the text starts and after it ends: during a foreword the
        // audio moves and the page does not, and saying otherwise is the
        // whole error this is here to avoid.
        let value: Int
        if clamped <= start {
            value = edition.firstPosition
        } else if clamped >= end {
            value = edition.lastPosition
        } else {
            let fraction = (clamped - start) / (end - start)
            let span = Double(edition.lastPosition - edition.firstPosition)
            value = edition.firstPosition + Int((fraction * span).rounded())
        }

        return FollowAlongPosition(
            value: min(max(value, edition.firstPosition), edition.lastPosition),
            total: edition.lastPosition,
            unit: edition.unit
        )
    }

    /// Progress through the audiobook, from a position the reader read off
    /// their own device. This is how the listener moves the *audio* to where
    /// they stopped reading.
    public static func progress(
        atPosition position: Int,
        edition: ReadingEdition
    ) -> Double? {
        guard edition.isUsable, edition.lastPosition > edition.firstPosition else { return nil }
        let clamped = min(max(position, edition.firstPosition), edition.lastPosition)
        let start = edition.usableStart
        let end = edition.usableEnd
        let fraction = Double(clamped - edition.firstPosition)
            / Double(edition.lastPosition - edition.firstPosition)
        return start + fraction * (end - start)
    }
}
