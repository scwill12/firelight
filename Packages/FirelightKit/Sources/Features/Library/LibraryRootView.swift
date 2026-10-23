import DesignSystem
import PlaybackKit
import SwiftUI

/// The signed-in app: what you are listening to, the whole library, search,
/// and the player that sits over all of them.
struct LibraryRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isShowingPlayer = false
    @Namespace private var playerNamespace

    var body: some View {
        TabView {
            Tab(L("Listening"), systemImage: "headphones") {
                HomeView()
            }
            Tab(L("Library"), systemImage: "square.grid.2x2") {
                BrowseView()
            }
            Tab(L("Search"), systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
        }
        .modifier(MiniPlayerAccessory(namespace: playerNamespace) { isShowingPlayer = true })
        .fullScreenCover(isPresented: $isShowingPlayer) {
            PlayerView(namespace: playerNamespace)
        }
    }
}

/// Puts the mini player above the tab bar.
///
/// iOS 26 has a proper slot for this (`tabViewBottomAccessory`), which keeps
/// it clear of content and matches the system's own players. On iOS 18 it is
/// an overlay with manual padding — visually close, and the deployment floor
/// is 18.
struct MiniPlayerAccessory: ViewModifier {
    let namespace: Namespace.ID
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabViewBottomAccessory {
                MiniPlayer(namespace: namespace, onTap: onTap)
            }
        } else {
            content.safeAreaInset(edge: .bottom) {
                MiniPlayer(namespace: namespace, onTap: onTap)
                    .padding(.bottom, Spacing.xs)
            }
        }
    }
}
