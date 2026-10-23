import DesignSystem
import Persistence
import SwiftUI

/// Browsing the whole library: grid or list, sorted, or grouped by author,
/// narrator, series or genre.
struct BrowseView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var items: [LibraryItemSummary] = []
    @State private var sort: LibrarySort = .title
    @State private var descending = false
    @AppStorage("firelight.browse.usesGrid") private var usesGrid = true

    private var library: LibraryController { environment.library }

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: Spacing.m, alignment: .top)]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "square.grid.2x2",
                        title: Text(L("Nothing to browse yet")),
                        message: Text(L("Your library will appear here once it has been fetched."))
                    )
                } else if usesGrid {
                    grid
                } else {
                    list
                }
            }
            .navigationTitle(Text(L("Library")))
            .navigationDestination(for: String.self) { ItemDetailView(itemID: $0) }
            .navigationDestination(for: LibraryFacet.self) { FacetListView(facet: $0) }
            .toolbar { toolbarContent }
            .refreshable { await library.refresh() }
            .task(id: refreshKey) { await reload() }
        }
    }

    /// Re-reads whenever anything that changes the result changes.
    private var refreshKey: String {
        "\(library.selectedLibraryID ?? "")|\(sort.rawValue)|\(descending)|\(library.itemCount)"
    }

    private var grid: some View {
        ScrollView {
            groupingLinks
            LazyVGrid(columns: columns, spacing: Spacing.l) {
                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        CoverCard(item: item, width: 110)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
        }
    }

    private var list: some View {
        List {
            Section { groupingLinks.listRowInsets(EdgeInsets()) }
            Section {
                ForEach(items) { item in
                    NavigationLink(value: item.id) { ItemRow(item: item) }
                }
            }
        }
        .listStyle(.plain)
    }

    private var groupingLinks: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) {
                ForEach(LibraryFacet.allCases, id: \.self) { facet in
                    NavigationLink(value: facet) {
                        Label(facet.title, systemImage: facet.symbol)
                            .font(Typography.caption)
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .firelightGlass(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
        }
        .scrollIndicators(.hidden)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if library.libraries.count > 1 {
                Menu {
                    Picker(L("Library"), selection: Binding(
                        get: { library.selectedLibraryID ?? "" },
                        set: { library.selectedLibraryID = $0 }
                    )) {
                        ForEach(library.libraries) { entry in
                            Text(verbatim: entry.name).tag(entry.id)
                        }
                    }
                } label: {
                    Label(L("Library"), systemImage: "books.vertical")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(L("Sort by"), selection: $sort) {
                    ForEach(LibrarySort.allCases, id: \.self) { option in
                        Text(verbatim: option.title).tag(option)
                    }
                }
                Toggle(L("Reversed"), isOn: $descending)
                Divider()
                Picker(L("View"), selection: $usesGrid) {
                    Text(L("Grid")).tag(true)
                    Text(L("List")).tag(false)
                }
            } label: {
                Label(L("View options"), systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func reload() async {
        items = await library.items(sort: sort, descending: descending)
    }
}

extension LibrarySort {
    var title: String {
        switch self {
        case .title: L("Title")
        case .author: L("Author")
        case .addedAt: L("Recently added")
        case .duration: L("Length")
        case .progress: L("Progress")
        }
    }
}

extension LibraryFacet {
    var title: String {
        switch self {
        case .author: L("Authors")
        case .narrator: L("Narrators")
        case .series: L("Series")
        case .genre: L("Genres")
        }
    }

    var symbol: String {
        switch self {
        case .author: "person"
        case .narrator: "waveform"
        case .series: "square.stack"
        case .genre: "tag"
        }
    }
}

/// The list of authors, narrators, series or genres.
struct FacetListView: View {
    let facet: LibraryFacet

    @Environment(AppEnvironment.self) private var environment
    @State private var values: [String] = []
    @State private var searchText = ""

    private var filtered: [String] {
        guard !searchText.isEmpty else { return values }
        return values.filter { $0.localizedStandardContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filtered, id: \.self) { value in
                NavigationLink(value: FacetSelection(facet: facet, value: value)) {
                    Text(verbatim: value)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: Text(facet.title))
        .overlay {
            if values.isEmpty {
                EmptyStateView(
                    systemImage: facet.symbol,
                    title: Text(L("Nothing here yet")),
                    message: Text(L("This appears once your library has been fetched."))
                )
            }
        }
        .navigationTitle(Text(verbatim: facet.title))
        .navigationDestination(for: FacetSelection.self) { selection in
            FacetItemsView(selection: selection)
        }
        .task { values = await environment.library.facetValues(facet) }
    }
}

struct FacetSelection: Hashable {
    let facet: LibraryFacet
    let value: String
}

/// Everything by one author, or in one series.
///
/// A series reads in series order with each book's progress beside it, which is
/// the one view that makes a long series navigable.
struct FacetItemsView: View {
    let selection: FacetSelection

    @Environment(AppEnvironment.self) private var environment
    @State private var items: [LibraryItemSummary] = []

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: item.id) {
                    HStack(spacing: Spacing.m) {
                        if selection.facet == .series, let sequence = item.seriesSequence {
                            Text(verbatim: Self.sequenceText(sequence))
                                .font(Typography.timecode)
                                .foregroundStyle(Palette.secondaryText)
                                .frame(minWidth: 28, alignment: .trailing)
                                .accessibilityLabel(L("Book \(Self.sequenceText(sequence))"))
                        }
                        ItemRow(item: item)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text(verbatim: selection.value))
        .navigationDestination(for: String.self) { ItemDetailView(itemID: $0) }
        .task { items = await environment.library.items(facet: selection.facet, value: selection.value) }
    }

    /// "5", not "5.0" — but "2.5" stays "2.5" for a novella.
    static func sequenceText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
