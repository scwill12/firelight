import ABSKit
import DesignSystem
import Foundation
import Observation
import Persistence

/// Drives the library screens.
///
/// Cache first, always: `load()` fills the screen from SwiftData with no
/// network at all, and `refresh()` quietly updates it afterwards. That order is
/// what makes the app open instantly and keep working on a plane.
@MainActor
@Observable
public final class LibraryController {
    public private(set) var libraries: [LibrarySummary] = []
    public private(set) var shelves: [SmartShelf] = []
    public private(set) var currentItem: LibraryItemSummary?
    public private(set) var itemCount = 0

    public var selectedLibraryID: String? {
        didSet {
            guard oldValue != selectedLibraryID else { return }
            Task { await load() }
        }
    }

    /// True only on a first sync with nothing cached — otherwise a refresh is
    /// invisible, because the screen already has content.
    public private(set) var isLoadingFromScratch = false
    public private(set) var isRefreshing = false
    public private(set) var refreshError: String?
    public private(set) var lastRefreshedAt: Date?

    @ObservationIgnored private let store: LibraryStore?
    @ObservationIgnored private let session: SessionController
    @ObservationIgnored private let shelfBuilder = SmartShelfBuilder()
    @ObservationIgnored private let spotlight = SpotlightIndexer()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(session: SessionController, persistence: PersistenceController?) {
        self.session = session
        self.store = persistence.map { LibraryStore(modelContainer: $0.container) }
    }

    private var serverID: UUID? { session.activeServer?.id }

    // MARK: - Cache

    public func load() async {
        guard let store, let serverID else {
            libraries = []
            shelves = []
            currentItem = nil
            return
        }
        do {
            libraries = try await store.libraries(serverID: serverID)
            if selectedLibraryID == nil {
                selectedLibraryID = libraries.first?.id
            }
            itemCount = try await store.itemCount(serverID: serverID)
            let items = try await store.items(serverID: serverID, libraryID: selectedLibraryID)
            currentItem = shelfBuilder.currentItem(from: items)
            shelves = shelfBuilder.shelves(from: items)
            lastRefreshedAt = libraries.first { $0.id == selectedLibraryID }?.lastRefreshedAt
        } catch {
            // A cache read failing is not worth a banner; the refresh will say so.
            libraries = []
            shelves = []
        }
    }

    public func items(sort: LibrarySort = .title, descending: Bool = false) async -> [LibraryItemSummary] {
        guard let store, let serverID else { return [] }
        return (try? await store.items(
            serverID: serverID,
            libraryID: selectedLibraryID,
            sort: sort,
            descending: descending
        )) ?? []
    }

    public func item(id: String) async -> LibraryItemSummary? {
        guard let store, let serverID else { return nil }
        return try? await store.item(serverID: serverID, itemID: id)
    }

    public func facetValues(_ facet: LibraryFacet) async -> [String] {
        guard let store, let serverID else { return [] }
        return (try? await store.facetValues(serverID: serverID, facet: facet, libraryID: selectedLibraryID)) ?? []
    }

    public func items(facet: LibraryFacet, value: String) async -> [LibraryItemSummary] {
        guard let store, let serverID else { return [] }
        return (try? await store.items(serverID: serverID, matching: facet, value: value)) ?? []
    }

    /// Searches the cache first, so results appear offline and instantly.
    /// The server is only asked when the cache has little to offer.
    public func search(_ query: String) async -> [LibraryItemSummary] {
        guard let store, let serverID else { return [] }
        let cached = (try? await store.search(serverID: serverID, query: query)) ?? []
        guard cached.count < 5, let client = session.client(), let libraryID = selectedLibraryID else {
            return cached
        }

        guard let remote = try? await client.search(libraryID: libraryID, query: query) else { return cached }
        let remoteItems = (remote.book ?? []).map(\.libraryItem) + (remote.podcast ?? []).map(\.libraryItem)
        guard !remoteItems.isEmpty else { return cached }

        try? await store.upsertItems(serverID: serverID, items: remoteItems)
        return (try? await store.search(serverID: serverID, query: query)) ?? cached
    }

    public func pickForMe() async -> LibraryItemSummary? {
        shelfBuilder.pickForMe(from: await items())
    }

    // MARK: - Refresh

    public func refresh() async {
        refreshTask?.cancel()
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        guard let store, let serverID, let client = session.client() else {
            refreshError = session.isOffline ? nil : "Not connected to a server."
            return
        }

        isLoadingFromScratch = itemCount == 0
        isRefreshing = true
        refreshError = nil
        defer {
            isRefreshing = false
            isLoadingFromScratch = false
        }

        do {
            let libraries = try await client.libraries()
            try await store.replaceLibraries(serverID: serverID, with: libraries)
            self.libraries = try await store.libraries(serverID: serverID)
            if selectedLibraryID == nil || !libraries.contains(where: { $0.id == selectedLibraryID }) {
                selectedLibraryID = libraries.first?.id
            }

            for library in libraries {
                if Task.isCancelled { return }
                let items = try await client.allLibraryItems(libraryID: library.id)
                try await store.upsertItems(serverID: serverID, items: items)
                try await store.pruneItems(
                    serverID: serverID,
                    libraryID: library.id,
                    keeping: Set(items.map(\.id))
                )
                try await store.markRefreshed(serverID: serverID, libraryID: library.id)
                // Show each library as it lands rather than after all of them.
                await load()
            }

            let progress = try await client.myProgress()
            try await store.applyProgress(serverID: serverID, progress: progress)
            await load()
            await indexForSpotlight()
        } catch is CancellationError {
            return
        } catch let error as APIError {
            refreshError = error.isTransient ? nil : error.localizedDescription
        } catch {
            refreshError = "Couldn't refresh the library."
        }
    }

    private func indexForSpotlight() async {
        guard let store, let serverID else { return }
        // Cap it: indexing 20,000 items on every refresh would cost more than
        // it is worth, and Spotlight is for what you reach for.
        guard let items = try? await store.items(serverID: serverID, sort: .addedAt, limit: 500) else { return }
        await spotlight.index(items)
    }

    /// Covers need the active server's address and proxy headers, which change
    /// on sign-in, on an account switch and on an address switch.
    ///
    /// The token is *not* here: `CoverImageProvider` reads it per request, so
    /// a rotation can't leave the shelves full of placeholders.
    public func coverConfiguration() async -> CoverConfiguration {
        guard let server = session.activeServer, let baseURL = session.baseURL(for: server.id) else {
            return CoverConfiguration()
        }
        return CoverConfiguration(
            baseURL: baseURL,
            headers: session.customHeaders(for: server.id)
        )
    }
}
