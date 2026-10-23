import Foundation
import ReadiumAdapterGCDWebServer
import ReadiumNavigator
import ReadiumShared
import ReadiumStreamer
import SwiftUI

/// Opens EPUB and CBZ files with Readium.
///
/// One opener and one HTTP server for the whole app: Readium serves a
/// publication's resources over a local server, and standing one up per book
/// would leak ports and sockets.
@MainActor
public final class EPUBPublicationOpener {
    public static let shared = EPUBPublicationOpener()

    /// Readium serves a publication's resources over a local HTTP server, and
    /// the navigator needs it on the main actor. One for the whole app:
    /// standing one up per book would leak ports.
    public let httpServer: HTTPServer

    private init() {
        self.httpServer = GCDHTTPServer(assetRetriever: AssetRetriever(httpClient: DefaultHTTPClient()))
    }

    /// Opens a file from disk.
    ///
    /// The retriever and opener are built per call rather than held: neither
    /// is `Sendable`, so sharing them across the `await` would be a data race
    /// under Swift 6. Building them is cheap compared with parsing a book.
    public nonisolated static func open(fileURL: URL) async throws -> Publication {
        guard let url = FileURL(url: fileURL) else {
            throw ReaderError.fileUnreadable
        }
        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )
        let asset = try await assetRetriever.retrieve(url: url).get()
        return try await opener.open(asset: asset, allowUserInteraction: false).get()
    }
}

/// The EPUB reading surface.
public struct EPUBReaderView: UIViewControllerRepresentable {
    private let publication: Publication
    private let initialLocator: Locator?
    private let settings: ReaderSettings
    private let onLocatorChange: (Locator) -> Void
    private let onSelection: (String, Locator) -> Void

    public init(
        publication: Publication,
        initialLocator: Locator?,
        settings: ReaderSettings,
        onLocatorChange: @escaping (Locator) -> Void,
        onSelection: @escaping (String, Locator) -> Void = { _, _ in }
    ) {
        self.publication = publication
        self.initialLocator = initialLocator
        self.settings = settings
        self.onLocatorChange = onLocatorChange
        self.onSelection = onSelection
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocator,
                config: EPUBNavigatorViewController.Configuration(
                    preferences: Self.preferences(from: settings)
                ),
                httpServer: EPUBPublicationOpener.shared.httpServer
            )
            navigator.delegate = context.coordinator
            context.coordinator.navigator = navigator
            return navigator
        } catch {
            // A book Readium cannot open is a real state, not a crash.
            return UIHostingController(rootView: ReaderFailureView())
        }
    }

    public func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onLocatorChange = onLocatorChange
        context.coordinator.onSelection = onSelection
        guard let navigator = context.coordinator.navigator else { return }
        navigator.submitPreferences(Self.preferences(from: settings))
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Maps Firelight's settings onto Readium's.
    static func preferences(from settings: ReaderSettings) -> EPUBPreferences {
        EPUBPreferences(
            columnCount: settings.allowsTwoColumns ? nil : .one,
            fontFamily: settings.font.familyName.map { FontFamily(rawValue: $0) },
            fontSize: settings.fontScale,
            hyphens: settings.isHyphenated,
            lineHeight: settings.lineHeight,
            pageMargins: max(0.5, settings.margin / 20),
            scroll: settings.pageTurn == .scroll,
            textAlign: settings.isJustified ? .justify : .start,
            theme: Self.theme(from: settings.theme)
        )
    }

    static func theme(from theme: ReaderTheme) -> ReadiumNavigator.Theme? {
        switch theme {
        case .white: .light
        case .sepia: .sepia
        case .grey, .trueBlack: .dark
        case .system: nil
        }
    }

    public final class Coordinator: NSObject, EPUBNavigatorDelegate {
        var navigator: EPUBNavigatorViewController?
        var onLocatorChange: ((Locator) -> Void)?
        var onSelection: ((String, Locator) -> Void)?

        public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            onLocatorChange?(locator)
        }

        public func navigator(_ navigator: VisualNavigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
            // A missing resource inside a book is not worth interrupting a
            // reader for; the page simply renders without it.
        }

        public func navigator(_ navigator: any Navigator, presentError error: NavigatorError) {
            // Readium asks us to present this. Nothing here is actionable by a
            // reader mid-page, so it is swallowed rather than shown.
        }
    }
}

struct ReaderFailureView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
            Text("This book couldn't be opened.")
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
