import SwiftUI

/// What stands in for artwork: before a cover loads, when an item has none,
/// and in previews.
///
/// Draws the item's initials over the brand gradient rather than a grey box, so
/// a shelf of un-loaded covers still reads as a shelf.
public struct CoverPlaceholder: View {
    private let title: String
    private let cornerRadius: CGFloat

    public init(title: String, cornerRadius: CGFloat = Radius.cover) {
        self.title = title
        self.cornerRadius = cornerRadius
    }

    private var initials: String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Palette.elevatedBackground)
            .overlay {
                // A whisper of the brand, not a flood of it. A shelf is mostly
                // artwork; a missing cover should sit quietly between two real
                // ones rather than pull the eye away from them.
                LinearGradient(
                    colors: [Palette.ember.opacity(0.22), Palette.accent.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                Text(initials)
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Palette.secondaryText)
                    .padding(Spacing.s)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.separator, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Cover placeholder") {
    HStack {
        CoverPlaceholder(title: "The Wind in the Willows")
            .frame(width: 100, height: 150)
        CoverPlaceholder(title: "Dune")
            .frame(width: 100, height: 150)
    }
    .padding()
}
