import DesignSystem
import SwiftUI

@main
@MainActor
struct FirelightWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// The watch app.
///
/// Phase 19 builds this out: Now Playing controls and books downloaded to the
/// watch for phone-free listening. Phase 0 ships the target so it builds
/// against the shared packages and so the watch scheme exists.
struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.s) {
                Image(systemName: "headphones")
                    .font(.title2)
                    .foregroundStyle(Palette.accent)
                Text("Nothing playing")
                    .font(Typography.itemSubtitle)
                    .foregroundStyle(Palette.primaryText)
                    .multilineTextAlignment(.center)
                Text("Start something on your iPhone.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .padding(Spacing.s)
            .navigationTitle("Firelight")
        }
    }
}

#Preview {
    WatchRootView()
}
