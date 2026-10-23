import SwiftUI

/// Spacing, radius and timing tokens. Nothing in Firelight hard-codes a number
/// that belongs here.
public enum Spacing {
    /// 2pt — hairline gaps inside a control.
    public static let hair: CGFloat = 2
    /// 4pt
    public static let xs: CGFloat = 4
    /// 8pt — the default gap between related elements.
    public static let s: CGFloat = 8
    /// 12pt
    public static let m: CGFloat = 12
    /// 16pt — the standard screen margin.
    public static let l: CGFloat = 16
    /// 24pt — between groups.
    public static let xl: CGFloat = 24
    /// 32pt
    public static let xxl: CGFloat = 32
    /// 48pt — above and below a centred empty state.
    public static let xxxl: CGFloat = 48
}

public enum Radius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 12
    /// Covers and cards.
    public static let cover: CGFloat = 10
    public static let sheet: CGFloat = 20
    public static let pill: CGFloat = 999
}

/// How cover artwork is laid out, everywhere it appears.
public enum CoverArt {
    /// Square. Audiobook artwork is square far more often than not, and the
    /// shelves used to mix a 2:3 slot with a 1:1 one, so the same book was a
    /// different shape on every screen. One ratio, cropped to fill, is what
    /// makes a shelf read as a shelf.
    public static let aspectRatio: CGFloat = 1

    /// The height of a cover laid out at `width`.
    public static func height(forWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }
}

public enum Elevation {
    public static let cardShadowRadius: CGFloat = 12
    public static let cardShadowY: CGFloat = 4
    public static let cardShadowOpacity: Double = 0.18
}

/// Motion tokens.
///
/// Every animation goes through `Motion.animation(reduceMotion:)` so Reduce
/// Motion is honoured in one place instead of being forgotten in twenty.
public enum Motion {
    public static let quick = Animation.spring(response: 0.3, dampingFraction: 0.85)
    public static let standard = Animation.spring(response: 0.45, dampingFraction: 0.82)
    /// The cover-to-player transition in Phase 3.
    public static let hero = Animation.spring(response: 0.55, dampingFraction: 0.8)

    /// How long the reader's bars stay up before getting out of the way.
    /// Long enough to read the chapter title, short enough not to sit over the
    /// page while someone is reading it.
    public static let chromeLinger = Duration.milliseconds(2500)

    /// Returns a crossfade instead of a spring when the user has asked for less
    /// motion, and `nil` is never returned so transitions stay predictable.
    public static func animation(_ base: Animation = Motion.standard, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : base
    }
}
