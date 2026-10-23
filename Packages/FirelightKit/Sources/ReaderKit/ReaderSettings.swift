import Foundation

/// The page's colours.
public enum ReaderTheme: String, Sendable, Hashable, Codable, CaseIterable {
    case white
    case sepia
    case grey
    /// Pure black, for OLED screens at night.
    case trueBlack
    /// Follows the system's light/dark setting.
    case system

    public var displayName: String {
        switch self {
        case .white: "White"
        case .sepia: "Sepia"
        case .grey: "Grey"
        case .trueBlack: "True black"
        case .system: "Match system"
        }
    }

    /// Background and text as sRGB components, for the themes that fix them.
    /// `system` resolves at render time and returns `nil` here.
    public var colors: (background: (r: Double, g: Double, b: Double), text: (r: Double, g: Double, b: Double))? {
        switch self {
        case .white: ((1.0, 1.0, 1.0), (0.11, 0.11, 0.12))
        case .sepia: ((0.98, 0.95, 0.88), (0.24, 0.19, 0.13))
        case .grey: ((0.26, 0.26, 0.28), (0.90, 0.90, 0.91))
        case .trueBlack: ((0.0, 0.0, 0.0), (0.78, 0.78, 0.80))
        case .system: nil
        }
    }
}

/// How pages advance.
public enum PageTurnStyle: String, Sendable, Hashable, Codable, CaseIterable {
    case slide
    case curl
    case scroll

    public var displayName: String {
        switch self {
        case .slide: "Slide"
        case .curl: "Curl"
        case .scroll: "Continuous scroll"
        }
    }
}

/// Typefaces Firelight ships.
///
/// All three are OFL, which is what lets them be bundled. Atkinson
/// Hyperlegible and OpenDyslexic are accessibility typefaces and are offered
/// for that reason, not as decoration.
public enum ReaderFont: String, Sendable, Hashable, Codable, CaseIterable {
    /// Whatever the publisher specified.
    case publisher
    case literata
    case atkinsonHyperlegible
    case openDyslexic
    case system

    public var displayName: String {
        switch self {
        case .publisher: "Publisher's choice"
        case .literata: "Literata"
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        case .openDyslexic: "OpenDyslexic"
        case .system: "System"
        }
    }

    /// The family name as the font file registers it, or nil to leave the
    /// publisher's own font alone.
    public var familyName: String? {
        switch self {
        case .publisher: nil
        case .literata: "Literata"
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        case .openDyslexic: "OpenDyslexic"
        case .system: "-apple-system"
        }
    }
}

/// Everything the reader lets you change about a page.
public struct ReaderSettings: Sendable, Hashable, Codable {
    public var font: ReaderFont
    /// A multiplier on the publisher's size, 0.5...3.0.
    public var fontScale: Double
    /// Multiplier, 1.0...3.0.
    public var lineHeight: Double
    /// Page margin in points, 0...80.
    public var margin: Double
    public var isJustified: Bool
    public var isHyphenated: Bool
    public var theme: ReaderTheme
    public var pageTurn: PageTurnStyle
    /// Two pages side by side on a wide screen.
    public var allowsTwoColumns: Bool

    public static let `default` = ReaderSettings(
        font: .publisher,
        fontScale: 1.0,
        lineHeight: 1.4,
        margin: 24,
        isJustified: false,
        isHyphenated: true,
        theme: .system,
        pageTurn: .slide,
        allowsTwoColumns: true
    )

    public init(
        font: ReaderFont,
        fontScale: Double,
        lineHeight: Double,
        margin: Double,
        isJustified: Bool,
        isHyphenated: Bool,
        theme: ReaderTheme,
        pageTurn: PageTurnStyle,
        allowsTwoColumns: Bool
    ) {
        self.font = font
        self.fontScale = min(max(fontScale, 0.5), 3.0)
        self.lineHeight = min(max(lineHeight, 1.0), 3.0)
        self.margin = min(max(margin, 0), 80)
        self.isJustified = isJustified
        self.isHyphenated = isHyphenated
        self.theme = theme
        self.pageTurn = pageTurn
        self.allowsTwoColumns = allowsTwoColumns
    }

    public mutating func adjustFontScale(by delta: Double) {
        fontScale = min(max(fontScale + delta, 0.5), 3.0)
    }

    private static let defaultsKey = "firelight.readerSettings"

    public static func load(from defaults: UserDefaults) -> ReaderSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data)
        else { return .default }
        return decoded
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
