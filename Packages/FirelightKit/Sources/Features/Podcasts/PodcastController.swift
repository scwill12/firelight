import ABSKit
import Foundation
import Observation
import Persistence

/// Drives the podcast screens and the Up Next queue.
@MainActor
@Observable
public final class PodcastController {
    public private(set) var episodes: [EpisodeSummary] = []
    public private(set) var showTitle = ""
    public private(set) var showAuthor: String?
    public private(set) var autoDownloadEnabled = false
    public private(set) var isLoading = false
    public private(set) var failure: String?

    /// Up Next, mixing books and episodes.
    public private(set) var queue: [QueueEntry] = SharedState.upNext

    @ObservationIgnored private let store: LibraryStore?
    @ObservationIgnored private let session: SessionController

    public init(session: SessionController, persistence: PersistenceController?) {
        self.session = session
        self.store = persistence.map { LibraryStore(modelContainer: $0.container) }
    }

    private var serverID: UUID? { session.activeServer?.id }

    /// Cache first, then refresh — same rule as the library.
    public func load(itemID: String) async {
        guard let store, let serverID else { return }
        episodes = (try? await store.episodes(serverID: serverID, itemID: itemID)) ?? []
        await refresh(itemID: itemID)
    }

    public func refresh(itemID: String) async {
        guard let store, let serverID, let client = session.client() else { return }
        isLoading = episodes.isEmpty
        failure = nil
        defer { isLoading = false }

        do {
            // Episodes only come back on the expanded item.
            let podcast = try await client.podcast(itemID: itemID)
            showTitle = podcast.media?.metadata.title ?? ""
            showAuthor = podcast.media?.metadata.author
            autoDownloadEnabled = podcast.media?.autoDownloadEpisodes ?? false

            let incoming = (podcast.media?.episodes ?? []).enumerated().map { index, episode in
                (
                    episodeID: episode.id,
                    title: episode.title ?? "Untitled episode",
                    subtitle: episode.subtitle,
                    summary: episode.description,
                    numbering: episode.numbering,
                    duration: episode.duration ?? 0,
                    sizeBytes: episode.sizeBytes ?? 0,
                    publishedAt: episode.publishedAt,
                    feedIndex: episode.index ?? index
                )
            }
            try await store.replaceEpisodes(serverID: serverID, itemID: itemID, episodes: incoming)

            if let progress = try? await client.myProgress() {
                try? await store.applyEpisodeProgress(serverID: serverID, progress: progress)
            }
            episodes = (try? await store.episodes(serverID: serverID, itemID: itemID)) ?? []
        } catch let error as APIError {
            failure = error.isTransient ? nil : error.localizedDescription
        } catch {
            failure = L("Couldn't load this podcast.")
        }
    }

    /// Asks the *server* to fetch anything new from the feed.
    public func checkForNewEpisodes(itemID: String) async {
        guard let client = session.client() else { return }
        _ = try? await client.checkForNewEpisodes(itemID: itemID)
        await refresh(itemID: itemID)
    }

    public func setAutoDownload(itemID: String, enabled: Bool) async {
        guard let client = session.client() else { return }
        do {
            try await client.setPodcastAutoDownload(itemID: itemID, enabled: enabled)
            autoDownloadEnabled = enabled
        } catch {
            failure = L("Couldn't change that setting.")
        }
    }

    // MARK: - Up Next

    public func enqueue(_ entry: QueueEntry) {
        guard !queue.contains(where: { $0.id == entry.id }) else { return }
        queue.append(entry)
        SharedState.upNext = queue
    }

    public func playNext(_ entry: QueueEntry) {
        queue.removeAll { $0.id == entry.id }
        queue.insert(entry, at: 0)
        SharedState.upNext = queue
    }

    public func remove(_ entry: QueueEntry) {
        queue.removeAll { $0.id == entry.id }
        SharedState.upNext = queue
    }

    public func move(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        SharedState.upNext = queue
    }

    public func clearQueue() {
        queue = []
        SharedState.upNext = []
    }

    /// Takes the next thing off the queue, which is what finishing an item does.
    public func dequeueNext() -> QueueEntry? {
        guard !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        SharedState.upNext = queue
        return next
    }
}
