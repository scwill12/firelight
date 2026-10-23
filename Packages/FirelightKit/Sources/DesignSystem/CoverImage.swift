import Nuke
import NukeUI
import SwiftUI

/// Where covers come from.
///
/// ABS serves covers from `/api/items/:id/cover`, which is behind the same auth
/// as everything else. The token goes in a header rather than the URL: ABS also
/// accepts `?token=`, but that would write the token into every image cache
/// key, disk cache filename and proxy log, which working rule 2 forbids.
///
/// The `Authorization` header is deliberately *not* part of this type. A token
/// stored here would be snapshotted into every `ImageRequest` the moment a view
/// asked for an image, and ABS rotates its access tokens — so a shelf would
/// quietly fill with placeholders until the app was relaunched.
/// `CoverImageProvider` resolves the token per request instead.
public struct CoverConfiguration: Sendable, Equatable {
    public var baseURL: URL?
    /// Per-server proxy headers, if the user configured any.
    public var headers: [String: String]

    public init(baseURL: URL? = nil, headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.headers = headers
    }

    public func coverURL(itemID: String) -> URL? {
        guard let baseURL else { return nil }
        return baseURL.appending(path: "api/items/\(itemID)/cover")
    }
}

/// Holds the image pipeline and the current credentials.
///
/// Injected through the environment rather than being a singleton, so a
/// preview, a test and the app can each have their own.
@MainActor
@Observable
public final class CoverImageProvider {
    /// `URLProtocol`s that cover loading must honour as well as the API client.
    ///
    /// Set once at launch. `DesignSystem` cannot see `DemoKit`, and should
    /// not — it is the layer that knows about drawing, not about servers.
    nonisolated(unsafe) public static var extraProtocolClasses: [AnyClass] = []

    /// Supplies a bearer token, or nil when nothing is signed in. Main-actor
    /// isolated because the session it reads is, and `@Sendable` because the
    /// image pipeline calls it from its own loading queue.
    public typealias TokenProvider = @Sendable @MainActor () async -> String?

    public private(set) var configuration: CoverConfiguration
    @ObservationIgnored public private(set) var pipeline: ImagePipeline

    /// - Parameters:
    ///   - accessToken: The active server's token, read at the moment each
    ///     request goes out. Nil in a preview or a test, where covers are
    ///     unauthenticated or absent.
    ///   - refreshAccessToken: Called once when ABS rejects the token, exactly
    ///     as `URLSessionHTTPClient` does for every other request.
    public init(
        configuration: CoverConfiguration = CoverConfiguration(),
        accessToken: TokenProvider? = nil,
        refreshAccessToken: TokenProvider? = nil
    ) {
        self.configuration = configuration
        // `withDataCache` keeps the original bytes on disk, which is what makes
        // a shelf of covers appear instantly in airplane mode.
        var pipelineConfiguration = ImagePipeline.Configuration
            .withDataCache(name: "com.colewilliams.firelight.covers")
        pipelineConfiguration.dataLoader = CoverDataLoader(
            accessToken: accessToken,
            refreshAccessToken: refreshAccessToken
        )
        self.pipeline = ImagePipeline(configuration: pipelineConfiguration)
    }

    public func update(_ configuration: CoverConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
    }

    public func request(itemID: String) -> ImageRequest? {
        guard let url = configuration.coverURL(itemID: itemID) else { return nil }
        var urlRequest = URLRequest(url: url)
        for (name, value) in configuration.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return ImageRequest(
            urlRequest: urlRequest,
            // The cache key is the URL alone, so a cover survives a sign-in,
            // a token rotation and an address switch.
            userInfo: [.imageIdKey: url.absoluteString]
        )
    }
}

/// Attaches the active server's token at the moment the request goes out, and
/// retries once with a fresh one when ABS says it is stale.
///
/// This is the image-pipeline half of what `URLSessionHTTPClient` does for
/// every other request. Without it a cover carries whatever token was current
/// when the view appeared, which is the wrong one after any rotation.
private final class CoverDataLoader: DataLoading {
    private let accessToken: CoverImageProvider.TokenProvider?
    private let refreshAccessToken: CoverImageProvider.TokenProvider?
    /// Built from a configuration rather than taken as-is: covers do not go
    /// through the app's `URLSession`, so any protocol the app registered —
    /// the demo library's, in particular — has to be registered here too or
    /// a demo shelf draws placeholders.
    private let inner: DataLoader = {
        let configuration = DataLoader.defaultConfiguration
        configuration.protocolClasses =
            CoverImageProvider.extraProtocolClasses + (configuration.protocolClasses ?? [])
        return DataLoader(configuration: configuration)
    }()

    init(
        accessToken: CoverImageProvider.TokenProvider?,
        refreshAccessToken: CoverImageProvider.TokenProvider?
    ) {
        self.accessToken = accessToken
        self.refreshAccessToken = refreshAccessToken
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        guard let accessToken else {
            return inner.loadData(with: request, didReceiveData: didReceiveData, completion: completion)
        }

        // The token is read asynchronously, so the handle is handed back before
        // there is a task to cancel.
        let handle = CoverLoadHandle()
        Task { [inner, refreshAccessToken] in
            let firstAttempt = Self.authorizing(request, with: await accessToken())
            let gate = CoverDataGate(didReceiveData)
            let task = inner.loadData(with: firstAttempt, didReceiveData: gate.send) { error in
                guard Self.isUnauthorized(error), let refreshAccessToken else {
                    completion(error)
                    return
                }
                // Anything the rejected attempt delivered must not reach the
                // decoder ahead of the retry's bytes.
                gate.close()
                Task {
                    guard let fresh = await refreshAccessToken() else {
                        completion(error)
                        return
                    }
                    let retry = inner.loadData(
                        with: Self.authorizing(request, with: fresh),
                        didReceiveData: didReceiveData,
                        completion: completion
                    )
                    handle.attach(retry)
                }
            }
            handle.attach(task)
        }
        return handle
    }

    private static func authorizing(_ request: URLRequest, with token: String?) -> URLRequest {
        guard let token else { return request }
        var authorized = request
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return authorized
    }

    private static func isUnauthorized(_ error: Error?) -> Bool {
        guard case .statusCodeUnacceptable(let code)? = error as? DataLoader.Error else { return false }
        return code == 401 || code == 403
    }
}

/// A `Cancellable` returned before the underlying task exists.
private final class CoverLoadHandle: Cancellable, @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var underlying: (any Cancellable)?

    func cancel() {
        let inFlight: (any Cancellable)? = lock.withLock {
            isCancelled = true
            defer { underlying = nil }
            return underlying
        }
        inFlight?.cancel()
    }

    /// Takes over an attempt, or cancels it if the load was already abandoned
    /// while the token was being read.
    func attach(_ task: any Cancellable) {
        let accepted: Bool = lock.withLock {
            guard !isCancelled else { return false }
            underlying = task
            return true
        }
        if !accepted { task.cancel() }
    }
}

/// Forwards streamed bytes until the attempt they belong to is abandoned.
private final class CoverDataGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = true
    private let downstream: @Sendable (Data, URLResponse) -> Void

    init(_ downstream: @escaping @Sendable (Data, URLResponse) -> Void) {
        self.downstream = downstream
    }

    @Sendable func send(_ data: Data, _ response: URLResponse) {
        guard lock.withLock({ isOpen }) else { return }
        downstream(data, response)
    }

    func close() {
        lock.withLock { isOpen = false }
    }
}

public extension EnvironmentValues {
    /// Nil until something with a signed-in server supplies one; covers then
    /// fall back to the placeholder, which is the correct offline behaviour.
    @Entry var coverImageProvider: CoverImageProvider?
}

/// An item's cover, with the placeholder standing in until it loads — and
/// staying put when there is no artwork at all.
public struct CoverImage: View {
    private let itemID: String
    private let title: String
    private let cornerRadius: CGFloat

    @Environment(\.coverImageProvider) private var provider

    public init(itemID: String, title: String, cornerRadius: CGFloat = Radius.cover) {
        self.itemID = itemID
        self.title = title
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        // `Color.clear` is what fixes the size. A `.aspectRatio(.fill)` image
        // reports the size it wants rather than the one it was proposed, so
        // laying it out directly made a 128pt cover 192pt wide — it spilled
        // past the screen margin on one side and over the title on the other.
        // Clear takes the proposed size exactly, and the overlay is clipped
        // to it.
        Color.clear
            .overlay {
                if let provider, let request = provider.request(itemID: itemID) {
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            CoverPlaceholder(title: title, cornerRadius: cornerRadius)
                        }
                    }
                    .pipeline(provider.pipeline)
                } else {
                    CoverPlaceholder(title: title, cornerRadius: cornerRadius)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
