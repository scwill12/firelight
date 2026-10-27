import ABSKit
import DemoKit
import DesignSystem
import Nuke
import Observation
import Persistence
import PlaybackKit
import MediaPlayer
import SwiftUI
import UIKit
import SyncEngine

/// Everything the UI is allowed to reach for, in one injected object.
///
/// No singletons: `live()` builds the real graph, `preview()` builds an
/// in-memory one, and a test builds whatever it needs. Later phases add the
/// session store, the sync engine and the download manager here.
@MainActor
@Observable
public final class AppEnvironment {
    /// `nil` when the store could not be opened, which the Settings screen
    /// reports rather than hiding behind a crash.
    public let persistence: PersistenceController?
    public let persistenceFailureDetail: String?
    public let keychain: KeychainStore
    public let device: DeviceIdentity
    /// Which server and account the app is acting as.
    public let session: SessionController
    /// The library cache and the screens that read it.
    public let library: LibraryController
    /// Covers, and the credentials they need.
    public let coverProvider: CoverImageProvider
    /// The audio player.
    public let player: PlaybackController
    /// Every position change in the app goes through here.
    public let sync: ProgressSyncService
    /// Downloads and storage.
    public let downloads: DownloadsController
    /// Reading.
    public let reader: ReaderController
    /// Where the listener would be in the printed book.
    public let followAlong: FollowAlongController
    /// The tip jar. Unlocks nothing.
    public let tipJar = TipJar()
    /// Podcast shows, episodes and the Up Next queue.
    public let podcasts: PodcastController
    /// Colours taken from the current cover, already contrast-checked.
    public private(set) var coverPalette: CoverPalette = .fallback
    /// Kids mode: a simplified library, locked behind the device passcode.
    public private(set) var isKidsMode: Bool = SharedState.isKidsModeEnabled

    public var servers: [ServerDescriptor] { session.servers }

    public init(
        persistence: PersistenceController?,
        persistenceFailureDetail: String? = nil,
        keychain: KeychainStore,
        device: DeviceIdentity
    ) {
        // Before the cover provider is built: its loader reads this when it
        // is constructed, so setting it afterwards is too late and a demo
        // shelf draws placeholders.
        CoverImageProvider.extraProtocolClasses = [DemoURLProtocol.self]

        self.persistence = persistence
        self.persistenceFailureDetail = persistenceFailureDetail
        self.keychain = keychain
        self.device = device
        let session = SessionController(keychain: keychain, persistence: persistence)
        self.session = session
        self.library = LibraryController(session: session, persistence: persistence)
        self.coverProvider = CoverImageProvider(
            accessToken: {
                guard let server = session.activeServer else { return nil }
                return await session.factory.authStore(for: server.id).accessToken()
            },
            refreshAccessToken: {
                guard let server = session.activeServer else { return nil }
                return try? await session.factory.authStore(for: server.id).refreshAccessToken()
            }
        )
        self.player = PlaybackController(
            client: { session.client() },
            baseURL: { session.activeServer.flatMap { session.baseURL(for: $0.id) } },
            accessToken: {
                guard let server = session.activeServer else { return nil }
                return await session.factory.authStore(for: server.id).accessToken()
            }
        )
        self.sync = ProgressSyncService(
            persistence: persistence,
            client: { session.client() },
            serverID: { session.activeServer?.id }
        )
        self.downloads = DownloadsController(session: session, persistence: persistence)
        self.followAlong = FollowAlongController()
        self.podcasts = PodcastController(session: session, persistence: persistence)

        let sync = self.sync
        self.reader = ReaderController(
            session: session,
            persistence: persistence,
            sync: ReaderController.ProgressSyncServiceBridge(
                record: { itemID, location, progress in
                    await sync.record(
                        itemID: itemID,
                        currentTime: nil,
                        duration: nil,
                        ebookLocation: location,
                        ebookProgress: progress
                    )
                },
                latest: { itemID in
                    guard let position = await sync.latestPosition(itemID: itemID) else { return nil }
                    return (position.ebookLocation, position.ebookProgress)
                }
            )
        )

        wirePlaybackToJournal()
        wirePlaybackToDownloads()
        wireCoverCredentials()
    }

    /// Covers live outside the API client, so they have to be told when the
    /// active connection changes rather than finding out by making a request.
    private func wireCoverCredentials() {
        session.onActiveConnectionChange = { [weak self] in
            await self?.refreshCoverCredentials()
        }
        // A new account has a different library behind it, and nothing else
        // asks for it: `start()` only runs at launch, so without this a first
        // sign-in showed an empty shelf until the user pulled to refresh.
        session.onActiveAccountChange = { [weak self] in
            guard let self else { return }
            await library.refresh()
            await downloads.reload()
        }
    }

    /// Positions go to the journal before they go anywhere else, and a
    /// position that arrives from elsewhere moves the player only through the
    /// resolver.
    private func wirePlaybackToJournal() {
        let sync = self.sync
        let player = self.player

        player.onRecordPosition = { itemID, episodeID, currentTime, duration, listened in
            Task {
                await sync.record(
                    itemID: itemID,
                    episodeID: episodeID,
                    currentTime: currentTime,
                    duration: duration,
                    listenedSinceLast: listened
                )
            }
        }
        player.onSessionBegan = { sync.beginSession() }
        player.onSessionEnded = { sync.endSession() }
        sync.onAdoptPosition = { position in
            player.applyRemotePosition(position)
        }
    }

    /// A downloaded book plays from disk, and knows where it was without
    /// asking the server.
    private func wirePlaybackToDownloads() {
        let downloads = self.downloads
        let sync = self.sync
        player.localTracksProvider = { itemID, episodeID in
            // A demo book is presented as already downloaded: AVPlayer does
            // not load through URLProtocol, so the bundle is how its audio
            // reaches the player. Real items fall straight through.
            let demo = DemoMode.localTracks(forItemID: itemID)
            if !demo.isEmpty {
                return demo.map {
                    AudioEngine.ResolvedTrack(url: $0.url, offset: $0.offset, duration: $0.duration)
                }
            }
            return await downloads.localTracks(forItemID: itemID, episodeID: episodeID)
        }
        player.offlinePositionProvider = { itemID in
            await sync.latestPosition(itemID: itemID)?.currentTime
        }
    }

    /// Builds the diagnostics report from what the app currently knows.
    ///
    /// Assembled here because this is the only place that can see all of it —
    /// and deliberately passed as plain counts, so nothing identifying can
    /// reach the report by accident.
    public func diagnosticsReport() async -> String {
        let checks = checker.run()
        return DiagnosticsReport.text(from: DiagnosticsReport.Input(
            appVersion: Bundle.main.shortVersion,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: device.label,
            serverCount: session.servers.count,
            serverVersions: session.activeServerVersion.map { [$0.description] } ?? [],
            activeAddressKind: session.activeAddress?.rawValue,
            isOffline: session.isOffline,
            libraryItemCount: library.itemCount,
            queuedProgressCount: sync.queuedCount,
            downloadCount: downloads.downloads.count,
            downloadBytes: downloads.totalBytes,
            appGroupAvailable: checks.first { $0.id == "appGroup" }?.outcome.didPass ?? false,
            keychainAvailable: checks.first { $0.id == "keychain" }?.outcome.didPass ?? false,
            databaseAvailable: checks.first { $0.id == "store" }?.outcome.didPass ?? false
        ))
    }

    /// Drains the queue and reconciles with the server. Called on launch, on
    /// reconnect and when the app comes back to the foreground.
    public func syncProgress() async {
        await sync.drain()
        await sync.refreshStreak()
        guard let client = session.client() else { return }
        if let progress = try? await client.myProgress() {
            await sync.reconcile(withServerProgress: progress)
        }
    }

    /// Opens the live connection, so another device's progress arrives at once.
    public func startLiveSync() async {
        guard let server = session.activeServer,
              let baseURL = session.baseURL(for: server.id),
              let token = await session.factory.authStore(for: server.id).accessToken()
        else { return }

        socketTask?.cancel()
        let headers = session.customHeaders(for: server.id)
        let sync = self.sync
        let library = self.library

        socketTask = Task { [weak self] in
            let client = ABSSocketClient(baseURL: baseURL, token: token, customHeaders: headers)
            self?.socketClient = client
            for await event in client.events() {
                switch event {
                case .progressUpdated(let progress):
                    guard let itemID = progress.libraryItemId else { continue }
                    await sync.receiveRemote(ProgressPosition(
                        itemID: itemID,
                        episodeID: progress.episodeId,
                        currentTime: progress.currentTime,
                        duration: progress.duration,
                        ebookLocation: progress.ebookLocation,
                        ebookProgress: progress.ebookProgress,
                        isFinished: progress.isFinished ?? false,
                        updatedAt: progress.lastUpdate ?? .now,
                        deviceID: "remote",
                        deviceLabel: "Another device"
                    ))
                case .libraryChanged:
                    await library.refresh()
                case .connected, .authenticated, .authenticationFailed, .disconnected:
                    break
                }
            }
        }
    }

    public func stopLiveSync() {
        socketTask?.cancel()
        socketTask = nil
        socketClient?.disconnect()
        socketClient = nil
    }

    @ObservationIgnored private var socketTask: Task<Void, Never>?
    @ObservationIgnored private var socketClient: ABSSocketClient?

    public func setKidsMode(_ enabled: Bool) {
        isKidsMode = enabled
        SharedState.isKidsModeEnabled = enabled
    }

    /// Opens an item in the player and tints the player from its cover.
    public func play(item: LibraryItemSummary) async {
        await updateCoverPalette(forItemID: item.id)
        followAlong.load(itemID: item.id)
        await player.open(itemID: item.id, title: item.title, author: item.author)
    }

    /// Takes the listener to a particular second of a book, opening it first
    /// when it is not the one already playing.
    ///
    /// Both `PlaybackController.seek` and `applyRemotePosition` do nothing
    /// unless that item is loaded, which is right for them — seeking a book
    /// you are not playing is meaningless. The history screens want the other
    /// behaviour: "take me there", which may mean opening the book first.
    /// Without this they looked tappable and silently did nothing.
    public func resume(itemID: String, at seconds: TimeInterval) async {
        if player.itemID != itemID {
            guard let item = await library.item(id: itemID) else { return }
            await play(item: item)
        }
        player.seek(to: seconds)
        Haptics.success()
    }

    /// Opens one podcast episode. The cover is the show's.
    public func play(episode: EpisodeSummary, showTitle: String) async {
        await updateCoverPalette(forItemID: episode.itemID)
        await player.open(
            itemID: episode.itemID,
            episodeID: episode.episodeID,
            title: episode.title,
            author: showTitle
        )
    }

    /// Loads the cover and derives a readable palette from it.
    ///
    /// Falls back silently: a cover that will not load is a reason to use the
    /// brand colours, not a reason to show an error.
    public func updateCoverPalette(forItemID itemID: String) async {
        guard let request = coverProvider.request(itemID: itemID) else {
            coverPalette = .fallback
            return
        }
        guard let response = try? await coverProvider.pipeline.image(for: request) else {
            coverPalette = .fallback
            return
        }
        let image = response
        coverPalette = await Task.detached(priority: .userInitiated) {
            CoverPaletteExtractor.palette(from: image)
        }.value
        player.artwork = Self.artwork(for: image)
    }

    /// Wraps a cover for the lock screen.
    ///
    /// `nonisolated` on purpose, and the reason is the whole point of this
    /// function. `MPMediaItemArtwork` calls its request handler on
    /// MediaPlayer's own queue, but a closure written inside a `@MainActor`
    /// method *inherits* that isolation — so Swift emits a runtime check that
    /// fails the moment MediaPlayer asks for the image, and the app is killed
    /// on the spot. That is what happened on every single play. Building the
    /// closure outside the actor leaves it with nothing to assert.
    ///
    /// The same trap caught the `AVPlayer` KVO handlers in `AudioEngine`: any
    /// closure handed to a framework that calls back on its own queue must be
    /// created somewhere non-isolated.
    nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Loads what is on disk, finds a reachable address, then refreshes in the
    /// background. Cache first: the screen is drawn before the network is asked
    /// anything.
    public func start() async {
        await session.load()
        SharedState.serverCount = session.servers.count
        await library.load()

        await session.connect()
        await refreshCoverCredentials()
        await syncProgress()
        await downloads.reload()
        await library.refresh()
        await downloads.applySmartRules(candidates: await library.items())
        await startLiveSync()
    }

    /// Covers are fetched with the active server's token and proxy headers, so
    /// the pipeline has to be told whenever either changes.
    public func refreshCoverCredentials() async {
        coverProvider.update(await library.coverConfiguration())
    }

    public static func live() -> AppEnvironment {
        var controller: PersistenceController?
        var failure: String?
        do {
            controller = try PersistenceController.shared()
        } catch PersistenceError.appGroupUnavailable {
            failure = "The App Group isn't available to this build."
        } catch {
            failure = "The database couldn't be opened."
        }
        return AppEnvironment(
            persistence: controller,
            persistenceFailureDetail: failure,
            keychain: KeychainStore(),
            device: DeviceIdentity.current()
        )
    }

    public static func preview() -> AppEnvironment {
        AppEnvironment(
            persistence: try? PersistenceController.inMemory(),
            keychain: KeychainStore(accessGroup: nil),
            device: DeviceIdentity(id: "preview", label: "iPhone")
        )
    }

    public var checker: FoundationChecker {
        FoundationChecker(
            keychain: keychain,
            storeOpened: persistence != nil,
            storeFailureDetail: persistenceFailureDetail
        )
    }
}
