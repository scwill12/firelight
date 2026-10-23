import DesignSystem
import Persistence
import SwiftUI

/// Search, answered from the cache first so it works offline and instantly.
struct SearchView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var query = ""
    @State private var results: [LibraryItemSummary] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: Text(L("Search your library")),
                        message: Text(L("Find a book by title, author, narrator, series or genre."))
                    )
                } else if results.isEmpty && !isSearching {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: Text(L("No matches")),
                        message: Text(L("Nothing in this library matches “\(query)”."))
                    )
                } else {
                    List {
                        ForEach(results) { item in
                            NavigationLink(value: item.id) { ItemRow(item: item) }
                        }
                    }
                    .listStyle(.plain)
                    .overlay(alignment: .top) {
                        if isSearching {
                            ProgressView().padding(Spacing.s)
                        }
                    }
                }
            }
            .navigationTitle(Text(L("Search")))
            .navigationDestination(for: String.self) { ItemDetailView(itemID: $0) }
        }
        .searchable(text: $query, prompt: Text(L("Title, author, narrator, series")))
        .onChange(of: query) { scheduleSearch() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            // The cache answers in microseconds; this delay is only to avoid
            // hitting the server on every keystroke when it falls through.
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            isSearching = true
            let found = await environment.library.search(text)
            if Task.isCancelled { return }
            results = found
            isSearching = false
        }
    }
}
