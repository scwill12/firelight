import Foundation
import SocketIO

/// The live connection to the server.
///
/// ABS pushes progress from the user's other devices over Socket.IO, which is
/// what makes "I paused on the iPad" show up here immediately rather than at
/// the next refresh.
///
/// Auth, verified against `SocketAuthority.js`: connect, emit `auth` with the
/// access token as a single string argument, then wait for `init` (success) or
/// `auth_failed`.
public final class ABSSocketClient: @unchecked Sendable {
    public enum Event: Sendable {
        case connected
        case authenticated(userID: String, username: String)
        case authenticationFailed(reason: String)
        /// Progress changed somewhere else.
        case progressUpdated(ABSMediaProgress)
        /// The library changed; the cache should refresh.
        case libraryChanged
        case disconnected
    }

    private let manager: SocketManager
    private let socket: SocketIOClient
    private let token: String
    private let lock = NSLock()
    private var continuation: AsyncStream<Event>.Continuation?

    public init(baseURL: URL, token: String, customHeaders: [String: String] = [:]) {
        self.token = token

        // A server hosted under a sub-path serves socket.io under it too.
        var path = baseURL.path
        if path.hasSuffix("/") { path.removeLast() }
        let socketPath = path.isEmpty ? "/socket.io" : "\(path)/socket.io"

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = ""
        let origin = components?.url ?? baseURL

        var config: SocketIOClientConfiguration = [
            .path(socketPath),
            .compress,
            .reconnects(true),
            .reconnectWait(2),
            .reconnectWaitMax(30),
            // Firelight never logs socket traffic: it carries progress and
            // would carry the token.
            .log(false),
        ]
        if !customHeaders.isEmpty {
            config.insert(.extraHeaders(customHeaders))
        }

        self.manager = SocketManager(socketURL: origin, config: config)
        self.socket = manager.defaultSocket
    }

    /// Connects and yields events until `disconnect()` is called.
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            lock.withLock { self.continuation = continuation }
            wireHandlers()
            socket.connect()

            continuation.onTermination = { [weak self] _ in
                self?.socket.disconnect()
            }
        }
    }

    public func disconnect() {
        socket.disconnect()
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }

    private func yield(_ event: Event) {
        lock.withLock { continuation?.yield(event) }
    }

    private func wireHandlers() {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.yield(.connected)
            // The server waits for this before associating a user.
            self.socket.emit("auth", self.token)
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.yield(.disconnected)
        }

        socket.on("init") { [weak self] data, _ in
            guard let payload = data.first as? [String: Any] else { return }
            self?.yield(.authenticated(
                userID: payload["userId"] as? String ?? "",
                username: payload["username"] as? String ?? ""
            ))
        }

        socket.on("auth_failed") { [weak self] data, _ in
            let reason = (data.first as? [String: Any])?["message"] as? String ?? "Authentication failed"
            self?.yield(.authenticationFailed(reason: reason))
        }

        // Progress from another device. The payload is a media progress
        // object; ABS has carried this under more than one name across
        // versions, so every known spelling is handled rather than assuming.
        for name in ["user_item_progress_updated", "user_media_progress_updated"] {
            socket.on(name) { [weak self] data, _ in
                guard let self else { return }
                guard let progress = Self.decodeProgress(from: data) else { return }
                self.yield(.progressUpdated(progress))
            }
        }

        for name in ["item_updated", "item_added", "item_removed", "items_updated", "items_added"] {
            socket.on(name) { [weak self] _, _ in
                self?.yield(.libraryChanged)
            }
        }
    }

    /// The progress object arrives either bare or wrapped in `{ data: … }`.
    static func decodeProgress(from data: [Any]) -> ABSMediaProgress? {
        guard let first = data.first else { return nil }
        let candidate: Any
        if let wrapper = first as? [String: Any], let inner = wrapper["data"] {
            candidate = inner
        } else {
            candidate = first
        }
        guard let object = candidate as? [String: Any],
              let json = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return try? ABSJSON.decoder.decode(ABSMediaProgress.self, from: json)
    }
}
