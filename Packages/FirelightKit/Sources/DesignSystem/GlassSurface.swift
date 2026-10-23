import SwiftUI

/// Liquid Glass where the OS has it, a material where it doesn't.
///
/// iOS 26 introduced the glass effect; iOS 18 is the deployment floor, so every
/// glass surface needs a fallback that looks deliberate rather than broken.
/// `.ultraThinMaterial` is that fallback: same translucency idea, no specular
/// behaviour.
public extension View {
    @ViewBuilder
    func firelightGlass<S: Shape>(in shape: S) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }

    func firelightGlass() -> some View {
        firelightGlass(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    /// A card on the shelf: elevated surface, continuous corners, soft shadow.
    func firelightCard(cornerRadius: CGFloat = Radius.cover) -> some View {
        self
            .background(Palette.elevatedBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: .black.opacity(Elevation.cardShadowOpacity),
                radius: Elevation.cardShadowRadius,
                x: 0,
                y: Elevation.cardShadowY
            )
    }
}
