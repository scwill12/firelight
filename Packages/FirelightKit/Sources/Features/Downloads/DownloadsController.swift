import ABSKit
import DownloadKit
import Foundation
import Observation
import Persistence
import PlaybackKit

/// Drives the downloads and storage screens.
@MainActor
@Observable
public final class DownloadsController {
    public private(set) var downloads: [DownloadSummary] = []
    public private(set) var totalBytes: Int64 = 0
    public var rules: SmartDownloadRules {
        didSet { Self.save(rules) }
    }

    @ObservationIgnored private let store: DownloadStore?
    @ObservationIgnored private let manager: BackgroundDownloadManager?
    @ObservationIgnored private let monitor = ConnectionMonitor()
    @ObservationIgnored private let session: SessionController

    public init(session: SessionController, persistence: PersistenceController?) {
        self.session = session
        self.rules = Self.load()
        if let persistence {
            let store = DownloadStore(modelContainer: persistence.container)
            self.store = store
            self.manager = BackgroundDownloadManager(store: store)
        } else {
            self.store = nil
            self.manager = nil
        }
        manager?.onChange = { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
        Task { await monitor.start() }
    }

    private var serverID: UUID? { session.activeServer?.id }

    public func reload() async {
        guard let store, let serverID else {
            downloads = []
            totalBytes = 0
            return
        }
        downloads = (try? await store.summaries(serverID: serverID)) ?? []
        totalBytes = downloads.reduce(0) { $0 + $1.bytesDownloaded }
    }

    public func state(forItemID itemID: String) -> DownloadState {
        downloads.first { $0.itemID == itemID }?.state ?? .notDownloaded
    }

    /// Starts a download, refusing politely on cellular when the user asked
    /// for Wi-Fi only.
    @discardableResult
    public func download(item: LibraryItemSummary, automatic: Bool = false) async -> String? {
        guard let manager, let serverID,
              let client = session.client(),
              let baseURL = session.baseURL(for: serverID)
        else { return L("Not connected to a server.") }

        if await !rules.allowsDownload(onExpensiveConnection: monitor.isExpensive) {
            return L("Downloads are set to Wi-Fi only.")
        }

        do {
            // The play session is what lists the audio files and their offsets.
            let request = PlaybackSessionRequest(
                deviceID: UUID().uuidString,
                clientVersion: Bundle.main.shortVersion,
                model: "iPhone",
                systemVersion: nil
            )
            let playback = try await client.openPlaybackSession(itemID: item.id, request: request)
            let absItem = try await client.item(id: item.id)
            try await manager.download(
                serverID: serverID,
                item: absItem,
                session: playback,
                title: item.title,
                author: item.author,
                baseURL: baseURL,
                accessToken: await session.factory.authStore(for: serverID).accessToken(),
                customHeaders: session.customHeaders(for: serverID),
                wasAutomatic: automatic
            )
            // Closing it immediately: this session was only for the file list.
            try? await client.closeSession(id: playback.id, currentTime: nil, timeListened: nil, duration: nil)
            await reload()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? L("Couldn't start the download.")
        }
    }

    public func remove(itemID: String) async {
        guard let manager, let serverID else { return }
        try? await manager.remove(serverID: serverID, itemID: itemID)
        await reload()
    }

    public func pause(itemID: String) async {
        guard let manager, let serverID else { return }
        await manager.pause(serverID: serverID, itemID: itemID)
        await reload()
    }

    /// Local files for the player, when an item is downloaded.
    public func localTracks(forItemID itemID: String, episodeID: String?) async -> [AudioEngine.ResolvedTrack] {
        guard let store, let serverID else { return [] }
        let tracks = (try? await store.localTracks(serverID: serverID, itemID: itemID, episodeID: episodeID)) ?? []
        return tracks.map {
            AudioEngine.ResolvedTrack(url: $0.url, offset: $0.startOffset, duration: $0.duration)
        }
    }

    /// Applies the automatic rules. Called after a library refresh.
    public func applySmartRules(candidates: [LibraryItemSummary]) async {
        guard let store, let serverID else { return }
        let downloadedIDs = Set(downloads.filter(\.state.isComplete).map(\.itemID))

        var ruleCandidates: [SmartDownloadRules.Candidate] = []
        for item in candidates {
            let finishedAt = try? await store.finishedAt(serverID: serverID, itemID: item.id)
            ruleCandidates.append(SmartDownloadRules.Candidate(
                itemID: item.id,
                seriesBaseName: item.seriesBaseName,
                seriesSequence: item.seriesSequence,
                progressFraction: item.progressFraction,
                isFinished: item.isFinished,
                isDownloaded: downloadedIDs.contains(item.id),
                finishedAt: finishedAt
            ))
        }

        for itemID in rules.itemsToDownload(from: ruleCandidates) {
            guard let item = candidates.first(where: { $0.id == itemID }) else { continue }
            _ = await download(item: item, automatic: true)
        }
        for itemID in rules.itemsToRemove(from: ruleCandidates) {
            await remove(itemID: itemID)
        }
    }

    /// Records when a book was finished, which the tidy-up rule needs.
    public func noteFinished(itemID: String) async {
        guard let store, let serverID else { return }
        try? await store.markFinished(serverID: serverID, itemID: itemID)
    }

    // MARK: - Settings

    private static let defaultsKey = "firelight.downloadRules"

    private static func load() -> SmartDownloadRules {
        guard let data = AppGroup.defaults?.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(SmartDownloadRules.self, from: data)
        else { return .default }
        return decoded
    }

    private static func save(_ rules: SmartDownloadRules) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        AppGroup.defaults?.set(data, forKey: defaultsKey)
    }
}
