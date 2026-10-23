import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A plain sRGB colour, so contrast maths can be written and tested without a
/// view, a trait collection or a running app.
public struct RGBColor: Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    #if canImport(UIKit)
    public var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    #endif
}

/// WCAG contrast, used wherever a colour is chosen at runtime.
///
/// Phase 3 tints the player from the cover art; this is what keeps that
/// legible. AA is 4.5:1 for body text and 3:1 for large text, from WCAG 2.1
/// success criterion 1.4.3.
public enum WCAG {
    public static let aaNormalText: Double = 4.5
    public static let aaLargeText: Double = 3.0
    public static let aaaNormalText: Double = 7.0

    /// Relative luminance, per the WCAG 2.1 definition.
    public static func relativeLuminance(_ color: RGBColor) -> Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
    }

    /// 1.0 (identical) to 21.0 (black on white).
    public static func contrastRatio(_ first: RGBColor, _ second: RGBColor) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        let lighter = max(a, b)
        let darker = min(a, b)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public static func meetsAA(foreground: RGBColor, background: RGBColor, largeText: Bool = false) -> Bool {
        contrastRatio(foreground, background) >= (largeText ? aaLargeText : aaNormalText)
    }

    /// Black or white, whichever is more readable on this background. The
    /// fallback every runtime-tinted surface uses when the brand colour fails.
    public static func preferredForeground(on background: RGBColor) -> RGBColor {
        let white = RGBColor(r: 1, g: 1, b: 1)
        let black = RGBColor(r: 0, g: 0, b: 0)
        return contrastRatio(white, background) >= contrastRatio(black, background) ? white : black
    }

    /// Darkens or lightens `foreground` until it passes AA on `background`,
    /// giving up and returning black or white rather than shipping unreadable
    /// text.
    public static func adjustedForAA(
        foreground: RGBColor,
        background: RGBColor,
        largeText: Bool = false
    ) -> RGBColor {
        if meetsAA(foreground: foreground, background: background, largeText: largeText) {
            return foreground
        }
        let target = preferredForeground(on: background)
        var candidate = foreground
        for step in 1...20 {
            let fraction = Double(step) / 20
            candidate = RGBColor(
                r: foreground.r + (target.r - foreground.r) * fraction,
                g: foreground.g + (target.g - foreground.g) * fraction,
                b: foreground.b + (target.b - foreground.b) * fraction,
                a: foreground.a
            )
            if meetsAA(foreground: candidate, background: background, largeText: largeText) {
                return candidate
            }
        }
        return target
    }
}
