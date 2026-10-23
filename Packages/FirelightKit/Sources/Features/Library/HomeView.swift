import DesignSystem
import Persistence
import SwiftUI

/// The home screen: what you are in the middle of, then the shelves.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var pickedItemID: String?
    @State private var isShowingSettings = false

    private var library: LibraryController { environment.library }

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoadingFromScratch {
                    LoadingStateView(title: Text(L("Fetching your library…")))
                } else if library.itemCount == 0 {
                    emptyState
                } else {
                    shelfScroll
                }
            }
            .navigationTitle(Text(L("Listening")))
            .navigationDestination(for: String.self) { itemID in
                ItemDetailView(itemID: itemID)
            }
            .refreshable { await library.refresh() }
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Label(L("Settings"), systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                UpNextView()
            } label: {
                Label(L("Up Next"), systemImage: "text.append")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    if let picked = await library.pickForMe() {
                        pickedItemID = picked.id
                    }
                }
            } label: {
                Label(L("Pick something for me"), systemImage: "dice")
            }
            .disabled(library.itemCount == 0)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "books.vertical",
            title: Text(L("Nothing on your shelf yet")),
            message: Text(L("Pull down to fetch your library from the server.")),
            actionLabel: Text(L("Refresh")),
            action: { Task { await library.refresh() } }
        )
    }

    private var shelfScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if let error = library.refreshError {
                    RefreshBanner(message: error) { Task { await library.refresh() } }
                        .padding(.horizontal, Spacing.l)
                }

                if let current = library.currentItem {
                    ContinueHero(item: current)
                        .padding(.horizontal, Spacing.l)
                }

                ForEach(library.shelves) { shelf in
                    ShelfRow(title: shelf.kind.title, items: shelf.items)
                }
            }
            .padding(.vertical, Spacing.l)
        }
        .navigationDestination(item: $pickedItemID) { itemID in
            ItemDetailView(itemID: itemID)
        }
    }
}

/// The one item you are in the middle of, given the room it deserves.
struct ContinueHero: View {
    let item: LibraryItemSummary

    /// Big enough to be the thing you look at first, small enough that a long
    /// title still gets three readable lines beside it.
    static let coverWidth: CGFloat = 132

    var body: some View {
        NavigationLink(value: item.id) {
            HStack(alignment: .top, spacing: Spacing.l) {
                CoverImage(itemID: item.id, title: item.title)
                    .frame(width: ContinueHero.coverWidth,
                           height: CoverArt.height(forWidth: ContinueHero.coverWidth))
                    .shadow(
                        color: .black.opacity(Elevation.cardShadowOpacity),
                        radius: Elevation.cardShadowRadius,
                        y: Elevation.cardShadowY
                    )

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(L("Continue"))
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .textCase(.uppercase)
                        .kerning(0.6)

                    Text(verbatim: item.title)
                        .font(Typography.itemTitle)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(2)

                    if let author = item.author {
                        Text(verbatim: author)
                            .font(Typography.itemSubtitle)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.s)

                    ProgressView(value: item.progressFraction)
                        .tint(Palette.accent)
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)

                    Text(verbatim: L("\(Format.duration(item.remainingTime)) left"))
                        .font(Typography.duration)
                        .foregroundStyle(Palette.secondaryText)
                }
                // Matches the cover's height so the progress bar lands on the
                // bottom edge of the artwork rather than floating above it.
                .frame(
                    maxWidth: .infinity,
                    minHeight: CoverArt.height(forWidth: Self.coverWidth),
                    alignment: .leading
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Continue: \(item.title)"))
        .accessibilityValue(L("\(Format.spokenDuration(item.remainingTime)) left"))
        .accessibilityAddTraits(.isButton)
    }
}

/// A refresh that failed, said once, without taking over the screen.
struct RefreshBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.notice)
            Text(verbatim: message)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 0)
            Button(L("Retry"), action: retry)
                .font(Typography.caption)
        }
        .padding(Spacing.m)
        .firelightGlass(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
