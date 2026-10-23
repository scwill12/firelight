import Foundation
#if canImport(WebKit) && os(iOS)
import WebKit

/// Converts MOBI and AZW3 to EPUB.
///
/// foliate-js parses the format and JSZip writes the package, both running in
/// a hidden `WKWebView` — there is no Swift MOBI parser worth the maintenance,
/// and foliate's is the one the whole ecosystem uses.
///
/// The web view is a liability if it outlives the conversion, so it is created
/// per conversion and torn down in every exit path.
@MainActor
public final class MOBIConverter: NSObject, FileConverting {
    public enum Event: Sendable {
        case progress(ConversionProgress)
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Output, Error>?
    private var progressHandler: (@MainActor (ConversionProgress) -> Void)?

    struct Output: Sendable {
        let base64: String
        let title: String
        let sections: Int
    }

    public override init() {
        super.init()
    }

    public func convert(fileAt url: URL, to target: ConversionTarget) async throws -> URL {
        guard target == .epub else {
            throw ConversionError.outputInvalid(reason: "This converter only writes EPUB.")
        }
        return try await convertToEPUB(fileAt: url, onProgress: nil)
    }

    /// Converts, reporting progress as it goes.
    ///
    /// Results are cached: converting a 40 MB book takes real time, and doing
    /// it again every time the reader opens would be indefensible.
    public func convertToEPUB(
        fileAt url: URL,
        onProgress: (@MainActor (ConversionProgress) -> Void)?
    ) async throws -> URL {
        let destination = Self.cacheURL(for: url)
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }

        // Cheap, local, and the commonest reason conversion is impossible.
        try MOBIInspector.requireConvertible(fileAt: url)

        progressHandler = onProgress
        onProgress?(.parsing)

        let data = try Data(contentsOf: url)
        let output = try await run(base64: data.base64EncodedString())

        guard let epub = Data(base64Encoded: output.base64) else {
            throw ConversionError.outputInvalid(reason: "The converter produced nothing readable.")
        }
        onProgress?(.validating)
        try Self.validate(epub)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try epub.write(to: destination, options: .atomic)
        onProgress?(.finished(destination))
        return destination
    }

    // MARK: - The web view

    private func run(base64: String) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                try startWebView(base64: base64)
            } catch {
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func startWebView(base64: String) throws {
        guard let html = Bundle.module.url(forResource: "converter", withExtension: "html") else {
            throw ConversionError.parseFailed(stage: "resources")
        }

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        for name in ["ready", "progress", "done", "failed"] {
            controller.add(self, name: name)
        }
        configuration.userContentController = controller
        // Nothing here needs to outlive the conversion or touch the network.
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        self.pendingBase64 = base64

        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    private var pendingBase64: String?

    private func finish(_ result: Result<Output, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        tearDown()
        switch result {
        case .success(let output): continuation?.resume(returning: output)
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private func tearDown() {
        let controller = webView?.configuration.userContentController
        for name in ["ready", "progress", "done", "failed"] {
            controller?.removeScriptMessageHandler(forName: name)
        }
        webView?.stopLoading()
        webView = nil
        pendingBase64 = nil
        progressHandler = nil
    }

    // MARK: - Output

    nonisolated static func cacheURL(for source: URL) -> URL {
        let name = source.deletingPathExtension().lastPathComponent
        return URL.cachesDirectory
            .appending(path: "Firelight/Converted", directoryHint: .isDirectory)
            .appending(path: "\(name).epub")
    }

    /// A converted file that is not actually an EPUB is worse than a failure,
    /// because it fails later and somewhere else.
    nonisolated static func validate(_ data: Data) throws {
        guard data.count > 100 else {
            throw ConversionError.outputInvalid(reason: "The converted file is empty.")
        }
        let bytes = [UInt8](data.prefix(58))
        guard bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
            throw ConversionError.outputInvalid(reason: "The converted file is not a ZIP.")
        }
        guard bytes.count >= 58,
              String(decoding: bytes[30..<38], as: UTF8.self) == "mimetype",
              String(decoding: bytes[38..<58], as: UTF8.self) == "application/epub+zip"
        else {
            throw ConversionError.outputInvalid(reason: "The converted file is not an EPUB.")
        }
    }
}

extension MOBIConverter: WKScriptMessageHandler {
    public nonisolated func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let name = message.name
        let body = message.body
        Task { @MainActor in
            self.handle(name: name, body: body)
        }
    }

    private func handle(name: String, body: Any) {
        switch name {
        case "ready":
            guard let base64 = pendingBase64, let webView else { return }
            pendingBase64 = nil
            webView.evaluateJavaScript("window.firelightConvert(`\(base64)`)") { [weak self] _, error in
                guard let error else { return }
                MainActor.assumeIsolated {
                    self?.finish(.failure(ConversionError.parseFailed(stage: "bridge")))
                }
                _ = error
            }

        case "progress":
            guard let payload = body as? [String: Any],
                  let stage = payload["stage"] as? String
            else { return }
            let fraction = (payload["fraction"] as? Double) ?? 0
            switch stage {
            case "parsing": progressHandler?(.parsing)
            case "writing": progressHandler?(.writing(fraction: fraction))
            case "validating": progressHandler?(.validating)
            default: break
            }

        case "done":
            guard let payload = body as? [String: Any],
                  let base64 = payload["base64"] as? String
            else {
                finish(.failure(ConversionError.outputInvalid(reason: "No output.")))
                return
            }
            finish(.success(Output(
                base64: base64,
                title: payload["title"] as? String ?? "",
                sections: payload["sections"] as? Int ?? 0
            )))

        case "failed":
            let reason = (body as? [String: Any])?["reason"] as? String ?? ""
            // foliate throws on an encrypted book too; map it to the message
            // the reader shows.
            let error: ConversionError = reason.localizedCaseInsensitiveContains("drm")
                || reason.localizedCaseInsensitiveContains("encrypt")
                ? .drmProtected
                : .parseFailed(stage: reason.isEmpty ? "conversion" : reason)
            finish(.failure(error))

        default:
            break
        }
    }
}
#endif
