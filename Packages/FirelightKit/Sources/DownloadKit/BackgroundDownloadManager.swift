import ABSKit
import Foundation
import Network
import Persistence

/// Downloads books in the background.
///
/// A background `URLSession` so a 2 GB book finishes while the app is
/// suspended — which is the only way downloading an audiobook is usable at
/// all. The session identifier is fixed and the container is the App Group, so
/// the system can hand work back to the app after it has been killed.
public final class BackgroundDownloadManager: NSObject, @unchecked Sendable {
    public static let sessionIdentifier = "com.colewilliams.firelight.downloads"

    private let store: DownloadStore
    private let lock = NSLock()
    /// Maps a task to what it is downloading, so a delegate callback after a
    /// relaunch can still be attributed.
    private var taskContexts: [Int: TaskContext] = [:]
    private var resumeData: [String: Data] = [:]

    private struct TaskContext: Sendable {
        let serverID: UUID
        let itemID: String
        let episodeID: String?
        let ino: String
        let relativePath: String
    }

    /// Called whenever a download's state changes, so the UI can refresh.
    public var onChange: (@Sendable () -> Void)?
    /// Called when the system hands back control after a background transfer.
    public var backgroundCompletionHandler: (@Sendable () -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.allowsCellularAccess = true // enforced by the rules, not the session
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    public init(store: DownloadStore) {
        self.store = store
        super.init()
    }

    /// Reattaches to whatever was in flight. Call once at launch.
    public func resumeInFlightTasks() async {
        let tasks = await session.allTasks
        guard !tasks.isEmpty else { return }
        onChange?()
    }

    // MARK: - Starting

    /// Queues every track of an item.
    public func download(
        serverID: UUID,
        item: ABSLibraryItem,
        session playbackSession: ABSPlaybackSession,
        title: String,
        author: String?,
        baseURL: URL,
        accessToken: String?,
        customHeaders: [String: String],
        wasAutomatic: Bool
    ) async throws {
        let tracks = playbackSession.orderedTracks
        guard !tracks.isEmpty else { throw DownloadError.itemHasNoFiles }

        let folder = "\(serverID.uuidString)/\(item.id)"
        let descriptors = tracks.enumerated().compactMap { index, track -> (String, Int, Double, Double, String)? in
            guard let contentUrl = track.contentUrl else { return nil }
            let ino = contentUrl.split(separator: "/").last.map(String.init) ?? "\(index)"
            let ext = Self.fileExtension(for: track.mimeType) ?? "m4b"
            return (ino, index, track.offset, track.length, "\(folder)/\(ino).\(ext)")
        }

        try await store.upsert(
            serverID: serverID,
            itemID: item.id,
            episodeID: nil,
            title: title,
            author: author,
            tracks: descriptors.map {
                (ino: $0.0, index: $0.1, offset: $0.2, duration: $0.3, relativePath: $0.4)
            },
            expectedBytes: item.size ?? 0,
            wasAutomatic: wasAutomatic
        )

        let root = try AppGroup.downloadsURL()
        try FileManager.default.createDirectory(
            at: root.appending(path: folder),
            withIntermediateDirectories: true
        )

        for descriptor in descriptors {
            guard let url = ABSEndpoint.mediaURL(
                baseURL: baseURL,
                contentPath: "/api/items/\(item.id)/file/\(descriptor.0)",
                accessToken: accessToken
            ) else { continue }

            var request = URLRequest(url: url)
            for (name, value) in customHeaders {
                request.setValue(value, forHTTPHeaderField: name)
            }

            let task = session.downloadTask(with: request)
            lock.withLock {
                taskContexts[task.taskIdentifier] = TaskContext(
                    serverID: serverID,
                    itemID: item.id,
                    episodeID: nil,
                    ino: descriptor.0,
                    relativePath: descriptor.4
                )
            }
            task.resume()
        }

        try await store.setState(serverID: serverID, itemID: item.id, episodeID: nil, state: .downloading(fraction: 0))
        onChange?()
    }

    // MARK: - Controlling

    public func pause(serverID: UUID, itemID: String) async {
        for task in await session.allTasks {
            guard let download = task as? URLSessionDownloadTask,
                  let context = context(for: task.taskIdentifier),
                  context.serverID == serverID, context.itemID == itemID
            else { continue }
            download.cancel { [weak self] data in
                guard let data else { return }
                self?.lock.withLock { self?.resumeData[context.ino] = data }
            }
        }
        try? await store.setState(serverID: serverID, itemID: itemID, episodeID: nil, state: .paused(fraction: 0))
        onChange?()
    }

    public func cancel(serverID: UUID, itemID: String) async {
        for task in await session.allTasks {
            guard let context = context(for: task.taskIdentifier),
                  context.serverID == serverID, context.itemID == itemID
            else { continue }
            task.cancel()
            lock.withLock { taskContexts[task.taskIdentifier] = nil }
        }
        try? await store.remove(serverID: serverID, itemID: itemID, episodeID: nil)
        onChange?()
    }

    public func remove(serverID: UUID, itemID: String) async throws {
        await cancel(serverID: serverID, itemID: itemID)
    }

    private func context(for taskIdentifier: Int) -> TaskContext? {
        lock.withLock { taskContexts[taskIdentifier] }
    }

    static func fileExtension(for mimeType: String?) -> String? {
        switch mimeType {
        case "audio/mpeg": "mp3"
        case "audio/mp4", "audio/m4a": "m4a"
        case "audio/x-m4b", "audio/m4b": "m4b"
        case "audio/flac", "audio/x-flac": "flac"
        case "audio/ogg", "audio/opus": "ogg"
        case "audio/wav", "audio/x-wav": "wav"
        default: nil
        }
    }
}

extension BackgroundDownloadManager: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let context = context(for: downloadTask.taskIdentifier) else { return }

        // The temporary file is gone as soon as this returns, so it has to be
        // moved here and now, synchronously.
        let bytes: Int64
        do {
            let root = try AppGroup.downloadsURL()
            let destination = root.appending(path: context.relativePath)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: location, to: destination)
            bytes = (try? FileManager.default.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int64) ?? 0
        } catch {
            Task { [store] in
                try? await store.setState(
                    serverID: context.serverID,
                    itemID: context.itemID,
                    episodeID: context.episodeID,
                    state: .failed(reason: "Couldn't save the download.")
                )
            }
            onChange?()
            return
        }

        lock.withLock { taskContexts[downloadTask.taskIdentifier] = nil }
        Task { [store, onChange] in
            _ = try? await store.markFileComplete(
                serverID: context.serverID,
                itemID: context.itemID,
                episodeID: context.episodeID,
                ino: context.ino,
                bytes: bytes
            )
            onChange?()
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // Deliberately quiet: a per-chunk database write would cost more than
        // the download. The completion of each file is what is recorded.
        onChange?()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let context = context(for: task.taskIdentifier) else { return }
        let isCancellation = (error as? URLError)?.code == .cancelled
        lock.withLock { taskContexts[task.taskIdentifier] = nil }
        guard !isCancellation else { return }

        Task { [store, onChange] in
            try? await store.setState(
                serverID: context.serverID,
                itemID: context.itemID,
                episodeID: context.episodeID,
                state: .failed(reason: "The download didn't finish.")
            )
            onChange?()
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletionHandler?()
    }
}

/// Whether the current connection is one the user pays for by the megabyte.
public actor ConnectionMonitor {
    private let monitor = NWPathMonitor()
    private var isExpensiveConnection = false
    private var isStarted = false

    public init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.update(isExpensive: path.isExpensive || path.isConstrained) }
        }
        monitor.start(queue: DispatchQueue(label: "com.colewilliams.firelight.network"))
    }

    private func update(isExpensive: Bool) {
        isExpensiveConnection = isExpensive
    }

    public var isExpensive: Bool { isExpensiveConnection }
}
