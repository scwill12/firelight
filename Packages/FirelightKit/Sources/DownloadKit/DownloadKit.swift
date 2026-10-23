import Foundation

/// A download's lifecycle, as the storage screen and the item view show it.
public enum DownloadState: Sendable, Hashable, Codable {
    case notDownloaded
    case queued
    /// 0...1
    case downloading(fraction: Double)
    case paused(fraction: Double)
    case downloaded(bytes: Int64)
    case failed(reason: String)

    public var isComplete: Bool {
        if case .downloaded = self { return true }
        return false
    }
}

/// The download seam. Phase 5 implements it on a background `URLSession`.
public protocol DownloadManaging: Sendable {
    func state(forItemID itemID: String, episodeID: String?) async -> DownloadState
    func download(itemID: String, episodeID: String?) async throws
    func pause(itemID: String, episodeID: String?) async
    func resume(itemID: String, episodeID: String?) async
    func remove(itemID: String, episodeID: String?) async throws
}

public enum DownloadError: Error, Sendable, Equatable {
    case notEnoughSpace(requiredBytes: Int64)
    /// The user's Wi-Fi-only setting is on and the device is on cellular.
    case wifiRequired
    case itemHasNoFiles
}
