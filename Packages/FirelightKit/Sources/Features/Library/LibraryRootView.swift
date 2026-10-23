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
    @Environment(AppEnvironment.self) private var environment
    let namespace: Namespace.ID
    let onTap: () -> Void

    func body(content: Content) -> some View {
        Group {
            // Attached only when there is something to show. Both the
            // accessory and the inset draw their own glass container, so
            // installing one around an empty mini player left a blank bar
            // hanging above the tab bar with nothing in it.
            if environment.player.itemID == nil {
                content
            } else if #available(iOS 26.0, *) {
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
}
