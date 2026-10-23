import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Colours taken from a cover, guaranteed to be readable.
///
/// The player tints itself from the artwork, which is lovely right up until a
/// dark cover produces grey-on-grey. Every colour here has been through the
/// WCAG check, so the tinting can never make text unreadable.
public struct CoverPalette: Sendable, Hashable {
    public let background: RGBColor
    /// Passes AA against `background`.
    public let primaryText: RGBColor
    /// Passes AA against `background`; used for the scrubber and controls.
    public let accent: RGBColor

    public init(background: RGBColor, primaryText: RGBColor, accent: RGBColor) {
        self.background = background
        self.primaryText = primaryText
        self.accent = accent
    }

    /// What the player uses before artwork has loaded.
    public static let fallback = CoverPalette(
        background: RGBColor(r: 0.09, g: 0.08, b: 0.09),
        primaryText: RGBColor(r: 0.96, g: 0.95, b: 0.93),
        accent: RGBColor(r: 1.0, g: 0.60, b: 0.25)
    )
}

public enum CoverPaletteExtractor {
    /// The pure core: a palette from a bag of pixels.
    ///
    /// Separated from image decoding so the colour rules can be tested with
    /// known inputs instead of a PNG.
    public static func palette(fromPixels pixels: [RGBColor]) -> CoverPalette {
        guard !pixels.isEmpty else { return .fallback }

        let count = Double(pixels.count)
        let average = RGBColor(
            r: pixels.reduce(0) { $0 + $1.r } / count,
            g: pixels.reduce(0) { $0 + $1.g } / count,
            b: pixels.reduce(0) { $0 + $1.b } / count
        )

        // Deepen the average into something a player can sit on. A washed-out
        // cover would otherwise give a flat, bright background that fights the
        // artwork for attention.
        let background = RGBColor(
            r: average.r * 0.32,
            g: average.g * 0.32,
            b: average.b * 0.34
        )

        let primaryText = WCAG.preferredForeground(on: background)

        // The most colourful pixel makes the best accent; fall back to the
        // brand ember when the cover is greyscale.
        let candidate = pixels.max { saturation($0) < saturation($1) } ?? average
        let accentSeed = saturation(candidate) < 0.15 ? CoverPalette.fallback.accent : candidate
        let accent = WCAG.adjustedForAA(foreground: accentSeed, background: background, largeText: true)

        return CoverPalette(background: background, primaryText: primaryText, accent: accent)
    }

    static func saturation(_ color: RGBColor) -> Double {
        let maximum = max(color.r, color.g, color.b)
        let minimum = min(color.r, color.g, color.b)
        guard maximum > 0 else { return 0 }
        return (maximum - minimum) / maximum
    }

    #if canImport(UIKit)
    /// Downsamples the cover and reads its pixels.
    ///
    /// 32×32 is plenty: this is about the overall cast of the artwork, and
    /// sampling the full image would be a main-thread stall for no gain.
    public static func palette(from image: UIImage, sampleSize: Int = 32) -> CoverPalette {
        guard let pixels = samplePixels(from: image, sampleSize: sampleSize) else { return .fallback }
        return palette(fromPixels: pixels)
    }

    static func samplePixels(from image: UIImage, sampleSize: Int) -> [RGBColor]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = sampleSize
        let height = sampleSize
        var buffer = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels: [RGBColor] = []
        pixels.reserveCapacity(width * height)
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = Double(buffer[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            pixels.append(RGBColor(
                r: Double(buffer[index]) / 255,
                g: Double(buffer[index + 1]) / 255,
                b: Double(buffer[index + 2]) / 255
            ))
        }
        return pixels.isEmpty ? nil : pixels
    }
    #endif
}
