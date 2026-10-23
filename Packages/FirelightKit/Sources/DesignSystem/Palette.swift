import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Firelight's semantic colours.
///
/// Semantic, not literal: call sites ask for `.primaryText`, never for a hex
/// value, so dark mode, Increase Contrast and the Phase 3 cover tinting all
/// have exactly one place to change.
///
/// The warm end of the palette is the brand: an ember read against a near-black
/// page, which is also what reads best in a dark room with an audiobook on.
public enum Palette {
    // MARK: - Brand

    /// The accent. A warm ember that stays legible on both page colours.
    public static let accent = dynamic(
        light: RGBColor(r: 0.78, g: 0.33, b: 0.05),
        dark: RGBColor(r: 1.0, g: 0.60, b: 0.25)
    )

    /// Used behind the launch screen and the player's dimmest state.
    public static let ember = dynamic(
        light: RGBColor(r: 0.62, g: 0.22, b: 0.04),
        dark: RGBColor(r: 0.85, g: 0.42, b: 0.12)
    )

    // MARK: - Surfaces

    public static let background = dynamic(
        light: RGBColor(r: 0.98, g: 0.97, b: 0.95),
        dark: RGBColor(r: 0.06, g: 0.06, b: 0.07)
    )

    /// Cards, sheets and shelves sitting on `background`.
    public static let elevatedBackground = dynamic(
        light: RGBColor(r: 1.0, g: 1.0, b: 1.0),
        dark: RGBColor(r: 0.11, g: 0.11, b: 0.12)
    )

    public static let separator = dynamic(
        light: RGBColor(r: 0.0, g: 0.0, b: 0.0, a: 0.10),
        dark: RGBColor(r: 1.0, g: 1.0, b: 1.0, a: 0.12)
    )

    // MARK: - Text

    public static let primaryText = dynamic(
        light: RGBColor(r: 0.10, g: 0.09, b: 0.08),
        dark: RGBColor(r: 0.96, g: 0.95, b: 0.93)
    )

    public static let secondaryText = dynamic(
        light: RGBColor(r: 0.36, g: 0.34, b: 0.32),
        dark: RGBColor(r: 0.70, g: 0.68, b: 0.66)
    )

    public static let destructive = dynamic(
        light: RGBColor(r: 0.72, g: 0.13, b: 0.10),
        dark: RGBColor(r: 1.0, g: 0.42, b: 0.37)
    )

    /// Reserved for "you are offline" and other non-error notices.
    public static let notice = dynamic(
        light: RGBColor(r: 0.45, g: 0.38, b: 0.10),
        dark: RGBColor(r: 0.95, g: 0.82, b: 0.40)
    )

    // MARK: - Resolution

    /// Builds a colour that resolves itself per appearance.
    ///
    /// watchOS has no light appearance and no `UIColor(dynamicProvider:)`, so
    /// the dark value is used there directly.
    static func dynamic(light: RGBColor, dark: RGBColor) -> Color {
        #if os(iOS) || targetEnvironment(macCatalyst)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor
        })
        #else
        return dark.color
        #endif
    }
}
