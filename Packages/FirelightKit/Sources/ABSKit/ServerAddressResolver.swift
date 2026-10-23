import Foundation

public struct ResolvedAddress: Sendable, Hashable {
    public let url: URL
    public let kind: ActiveAddress

    public init(url: URL, kind: ActiveAddress) {
        self.url = url
        self.kind = kind
    }
}

/// Picks which of a server's two addresses to use, right now.
///
/// Both are probed at once rather than in sequence, so being away from home
/// costs nothing. The local address wins any tie: when both answer, the LAN
/// one is faster, cheaper and does not leave the house.
///
/// The prober is injected, which keeps this testable without a network and
/// lets the caller decide the timeout — a probe that hangs is the whole reason
/// users think an app is broken.
public struct ServerAddressResolver: Sendable {
    public typealias Prober = @Sendable (URL) async -> Bool

    private let probe: Prober

    public init(probe: @escaping Prober) {
        self.probe = probe
    }

    /// The production prober: `GET /ping` with a short timeout and the
    /// server's own custom headers attached.
    /// - Parameter extraProtocolClasses: `URLProtocol`s this prober must
    ///   honour. The session here is its own — ephemeral, with its own
    ///   timeouts — so anything registered on the app's session is invisible
    ///   to it unless it is passed in. The demo library is served by one, and
    ///   without this its host never resolves: the app falls back to its
    ///   cache, which looks like a library with no covers.
    public static func live(
        customHeaders: CustomHeaderProviding = StaticCustomHeaders(),
        timeout: TimeInterval = 3,
        sessionDelegate: URLSessionDelegate? = nil,
        extraProtocolClasses: [AnyClass] = []
    ) -> ServerAddressResolver {
        ServerAddressResolver { url in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            configuration.timeoutIntervalForResource = timeout
            configuration.waitsForConnectivity = false
            configuration.protocolClasses =
                extraProtocolClasses + (configuration.protocolClasses ?? [])
            let session = URLSession(
                configuration: configuration,
                delegate: sessionDelegate,
                delegateQueue: nil
            )
            defer { session.finishTasksAndInvalidate() }
            let client = ABSClient(
                http: URLSessionHTTPClient(baseURL: url, session: session, customHeaders: customHeaders)
            )
            return await client.ping()
        }
    }

    public func resolve(_ descriptor: ServerDescriptor) async -> ResolvedAddress? {
        guard let localURL = descriptor.localURL, localURL != descriptor.remoteURL else {
            return await probe(descriptor.remoteURL)
                ? ResolvedAddress(url: descriptor.remoteURL, kind: .remote)
                : nil
        }

        async let localReachable = probe(localURL)
        async let remoteReachable = probe(descriptor.remoteURL)
        let (local, remote) = await (localReachable, remoteReachable)

        if local { return ResolvedAddress(url: localURL, kind: .local) }
        if remote { return ResolvedAddress(url: descriptor.remoteURL, kind: .remote) }
        return nil
    }
}
