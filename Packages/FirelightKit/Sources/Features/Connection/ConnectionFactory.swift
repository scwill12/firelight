import ABSKit
import DemoKit
import Foundation

/// Builds the clients that talk to a server, with the right headers, the right
/// tokens and the right certificate trust attached.
///
/// One place that knows how a connection is assembled, so no feature can
/// accidentally build a client that skips the user's proxy headers or their
/// pinned certificate.
@MainActor
final class ConnectionFactory {
    let keychain: KeychainStore
    let trust: CertificateTrustCoordinator

    private var authStores: [UUID: AuthStore] = [:]
    private let session: URLSession
    private let pinningDelegate: PinnedCertificateSessionDelegate

    init(keychain: KeychainStore, trust: CertificateTrustCoordinator = CertificateTrustCoordinator()) {
        self.keychain = keychain
        self.trust = trust
        self.pinningDelegate = PinnedCertificateSessionDelegate(store: trust)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        // Claims `demo.firelight.invalid` and nothing else, so the demo
        // library is served by the same client, decoders and screens as a real
        // server. Every other host goes over the network untouched.
        configuration.protocolClasses =
            [DemoURLProtocol.self] + (configuration.protocolClasses ?? [])
        self.session = URLSession(configuration: configuration, delegate: pinningDelegate, delegateQueue: nil)
    }

    func authStore(for serverID: UUID) -> AuthStore {
        if let existing = authStores[serverID] { return existing }
        let store = AuthStore(serverID: serverID, keychain: keychain)
        authStores[serverID] = store
        return store
    }

    func headerStore(for serverID: UUID) -> CustomHeaderStore {
        CustomHeaderStore(serverID: serverID, keychain: keychain)
    }

    /// A client with no credentials, for `/status`, `/ping` and `/login`.
    func anonymousClient(baseURL: URL, serverID: UUID?) -> ABSClient {
        let headers: CustomHeaderProviding = serverID.map { headerStore(for: $0) } ?? StaticCustomHeaders()
        return anonymousClient(baseURL: baseURL, headers: headers)
    }

    /// The same, with headers supplied directly — used during onboarding, when
    /// the server has no id yet but may still sit behind a proxy that needs
    /// them before it will answer at all.
    func anonymousClient(baseURL: URL, headers: CustomHeaderProviding) -> ABSClient {
        ABSClient(
            http: URLSessionHTTPClient(baseURL: baseURL, session: session, customHeaders: headers)
        )
    }

    func resolver(headers: CustomHeaderProviding) -> ServerAddressResolver {
        ServerAddressResolver.live(customHeaders: headers, timeout: 3, sessionDelegate: pinningDelegate)
    }

    /// A client that signs its requests and renews its own token.
    func authenticatedClient(serverID: UUID, baseURL: URL) -> ABSClient {
        let tokens = authStore(for: serverID)
        let headers = headerStore(for: serverID)
        let session = self.session

        // The refresh call is itself unauthenticated, so it gets a plain client.
        // Configured here because the store cannot build one without us.
        Task {
            await tokens.configure {
                ABSClient(
                    http: URLSessionHTTPClient(baseURL: baseURL, session: session, customHeaders: headers)
                )
            }
        }

        return ABSClient(
            http: URLSessionHTTPClient(
                baseURL: baseURL,
                session: session,
                tokens: tokens,
                customHeaders: headers
            )
        )
    }

    /// The resolver used for the home/away race, carrying this server's headers
    /// and certificate trust.
    func resolver(for serverID: UUID?) -> ServerAddressResolver {
        let headers: CustomHeaderProviding = serverID.map { headerStore(for: $0) } ?? StaticCustomHeaders()
        return ServerAddressResolver.live(
            customHeaders: headers,
            timeout: 3,
            sessionDelegate: pinningDelegate
        )
    }
}
