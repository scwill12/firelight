import DesignSystem
import PlaybackKit
import SwiftUI

/// The signed-in app, laid out for whatever it is running on.
///
/// A sidebar on iPad and Mac, tabs on iPhone. Not because the platforms demand
/// different code, but because a tab bar on a 13-inch screen wastes most of it
/// and a sidebar on a phone leaves no room for the content.
struct AdaptiveRootView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var isShowingPlayer = false
    @State private var selection: SidebarItem? = .listening
    @Namespace private var playerNamespace

    enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
        case listening, library, search, upNext, downloads

        var id: String { rawValue }

        var title: String {
            switch self {
            case .listening: L("Listening")
            case .library: L("Library")
            case .search: L("Search")
            case .upNext: L("Up Next")
            case .downloads: L("Downloads")
            }
        }

        var symbol: String {
            switch self {
            case .listening: "headphones"
            case .library: "square.grid.2x2"
            case .search: "magnifyingglass"
            case .upNext: "text.append"
            case .downloads: "arrow.down.circle"
            }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                sidebar
            } else {
                tabs
            }
        }
        .fullScreenCover(isPresented: $isShowingPlayer) {
            PlayerView(namespace: playerNamespace)
        }
    }

    // MARK: - iPad and Mac

    private var sidebar: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { entry in
                NavigationLink(value: entry) {
                    Label(entry.title, systemImage: entry.symbol)
                }
            }
            .navigationTitle(Text(L("Firelight")))
            .safeAreaInset(edge: .bottom) {
                MiniPlayer(namespace: playerNamespace) { isShowingPlayer = true }
                    .padding(.bottom, Spacing.s)
            }
        } detail: {
            detail
        }
        // The split view provides navigation, so the panes must not add their own.
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .listening, nil: HomeView()
        case .library: BrowseView()
        case .search: SearchView()
        case .upNext: NavigationStack { UpNextView() }
        case .downloads: NavigationStack { StorageView() }
        }
    }

    // MARK: - iPhone

    private var tabs: some View {
        TabView {
            Tab(L("Listening"), systemImage: "headphones") { HomeView() }
            Tab(L("Library"), systemImage: "square.grid.2x2") { BrowseView() }
            Tab(L("Search"), systemImage: "magnifyingglass", role: .search) { SearchView() }
        }
        .modifier(MiniPlayerAccessory(namespace: playerNamespace) { isShowingPlayer = true })
    }
}

/// Keyboard shortcuts, for the platforms that have a keyboard.
///
/// The set is deliberately small and conventional: space to play, arrows to
/// skip. Anything a user has to learn is a shortcut they will not use.
public struct FirelightCommands: Commands {
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some Commands {
        CommandMenu(Text(L("Playback"))) {
            Button(environment.player.isPlaying ? L("Pause") : L("Play")) {
                environment.player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(environment.player.itemID == nil)

            Button(L("Skip Forward")) { environment.player.skipForward() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button(L("Skip Back")) { environment.player.skipBackward() }
                .keyboardShortcut(.leftArrow, modifiers: [])

            Divider()

            Button(L("Next Chapter")) { environment.player.nextChapter() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button(L("Previous Chapter")) { environment.player.previousChapter() }
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Button(L("Faster")) {
                environment.player.setRate(environment.player.rate.stepped(by: 1))
            }
            .keyboardShortcut("]", modifiers: .command)
            Button(L("Slower")) {
                environment.player.setRate(environment.player.rate.stepped(by: -1))
            }
            .keyboardShortcut("[", modifiers: .command)

            Divider()

            Button(L("Add Bookmark")) {
                Task { await environment.player.addBookmark(title: nil) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(environment.player.itemID == nil)
        }

        CommandGroup(after: .toolbar) {
            Button(L("Refresh Library")) {
                Task { await environment.library.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}
