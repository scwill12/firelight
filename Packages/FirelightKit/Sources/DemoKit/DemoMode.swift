import Foundation

/// Firelight with no server attached.
///
/// A client for a self-hosted server has a chicken-and-egg problem: you cannot
/// see whether you want it until you have stood up the thing it talks to. That
/// is true for someone browsing the App Store and it is true for the reviewer
/// deciding whether the app works at all — and a reviewer who cannot get past
/// the first screen rejects the app.
///
/// So Firelight ships a small library of its own. It is not a mock in the
/// testing sense: the app runs its ordinary code against it, over its ordinary
/// HTTP client, and the only thing that differs is which `URLProtocol` answers.
public enum DemoMode {
    /// A host that cannot resolve, on a reserved TLD, so a request that
    /// escaped the protocol would fail loudly rather than reach a stranger.
    /// RFC 2606 keeps `.invalid` permanently unregistrable.
    public static let host = "demo.firelight.invalid"

    public static let baseURL = URL(string: "https://\(host)")!

    public static let serverName = "Demo library"
    public static let username = "demo"
    public static let password = "demo"

    /// The demo server is identified by its address. It is added through the
    /// ordinary path, which mints its own id, so there is no fixed id to
    /// compare against.
    public static func isDemo(url: URL) -> Bool { url.host() == host }
}

/// One bundled audio file, positioned in book time.
///
/// `PlaybackKit` owns the type the player actually wants; this carries the
/// three facts needed to build one without `DemoKit` having to depend on it.
public struct DemoTrack: Sendable, Hashable {
    public let url: URL
    public let offset: TimeInterval
    public let duration: TimeInterval
}

public extension DemoMode {
    /// The bundled audio for a demo book, as though it had been downloaded.
    ///
    /// Empty for anything that is not a demo book, which is what makes this
    /// safe to ask on every play: a real item falls straight through to the
    /// real downloads.
    static func localTracks(forItemID itemID: String) -> [DemoTrack] {
        guard let book = DemoCatalogue.book(id: itemID) else { return [] }
        return book.tracks.compactMap { track in
            guard let url = DemoBundle.url(named: track.resource, extension: "m4a") else { return nil }
            return DemoTrack(url: url, offset: track.offset, duration: track.duration)
        }
    }

    /// The bundled ebook or comic for a demo book.
    static func localFile(forItemID itemID: String) -> URL? {
        guard let book = DemoCatalogue.book(id: itemID),
              let name = book.fileResource,
              let ext = book.fileExtension
        else { return nil }
        return DemoBundle.url(named: name, extension: ext)
    }
}
