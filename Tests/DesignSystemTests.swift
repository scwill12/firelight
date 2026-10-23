import Testing
@testable import DesignSystem

@Suite("WCAG contrast")
struct WCAGTests {
    private let white = RGBColor(r: 1, g: 1, b: 1)
    private let black = RGBColor(r: 0, g: 0, b: 0)

    @Test("Matches the reference values from the WCAG definition")
    func knownRatios() {
        #expect(abs(WCAG.contrastRatio(black, white) - 21.0) < 0.01)
        #expect(abs(WCAG.contrastRatio(white, white) - 1.0) < 0.001)
        // #777777 on white is the canonical 4.48:1 near-miss.
        let grey = RGBColor(r: 0.4667, g: 0.4667, b: 0.4667)
        #expect(abs(WCAG.contrastRatio(grey, white) - 4.48) < 0.05)
    }

    @Test("AA is 4.5 for body text and 3.0 for large text")
    func aaThresholds() {
        let grey = RGBColor(r: 0.4667, g: 0.4667, b: 0.4667)
        #expect(!WCAG.meetsAA(foreground: grey, background: white))
        #expect(WCAG.meetsAA(foreground: grey, background: white, largeText: true))
    }

    @Test("Picks the more readable of black and white")
    func preferredForeground() {
        #expect(WCAG.preferredForeground(on: white) == black)
        #expect(WCAG.preferredForeground(on: black) == white)
        let ember = RGBColor(r: 0.85, g: 0.42, b: 0.12)
        #expect(WCAG.preferredForeground(on: ember) == black)
    }

    @Test("Adjusts a failing colour until it passes, which cover tinting depends on")
    func adjustment() {
        let background = RGBColor(r: 0.85, g: 0.42, b: 0.12) // a warm cover
        let brandOnTop = RGBColor(r: 1.0, g: 0.60, b: 0.25)
        #expect(!WCAG.meetsAA(foreground: brandOnTop, background: background))

        let fixed = WCAG.adjustedForAA(foreground: brandOnTop, background: background)
        #expect(WCAG.meetsAA(foreground: fixed, background: background))
    }

    @Test("A colour that already passes is left alone")
    func noUnnecessaryAdjustment() {
        let adjusted = WCAG.adjustedForAA(foreground: black, background: white)
        #expect(adjusted == black)
    }

    @Test("Every palette pairing the app ships meets AA in both appearances")
    func paletteMeetsAA() {
        // Light
        let lightBackground = RGBColor(r: 0.98, g: 0.97, b: 0.95)
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 0.10, g: 0.09, b: 0.08), background: lightBackground))
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 0.36, g: 0.34, b: 0.32), background: lightBackground))
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 0.72, g: 0.13, b: 0.10), background: lightBackground))

        // Dark
        let darkBackground = RGBColor(r: 0.06, g: 0.06, b: 0.07)
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 0.96, g: 0.95, b: 0.93), background: darkBackground))
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 0.70, g: 0.68, b: 0.66), background: darkBackground))
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 1.0, g: 0.42, b: 0.37), background: darkBackground))
        #expect(WCAG.meetsAA(foreground: RGBColor(r: 0.95, g: 0.82, b: 0.40), background: darkBackground))
    }
}
