import Foundation

/// Routes requests for a mock server's host to that server. Registered only on
/// the session a `MockABSServer` hands out, so nothing else is intercepted.
public final class MockABSURLProtocol: URLProtocol {
    public override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host() else { return false }
        return MockRegistry.shared.server(forHost: host) != nil
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        guard let url = request.url,
              let host = url.host(),
              let server = MockRegistry.shared.server(forHost: host)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = components?.path ?? "/"
        if !server.basePath.isEmpty, path.hasPrefix(server.basePath) {
            path = String(path.dropFirst(server.basePath.count))
            if path.isEmpty { path = "/" }
        }

        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value ?? ""
        }

        // URLProtocol strips the body into a stream for some methods; read both.
        let body = request.httpBody ?? request.bodyStreamData()

        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: path,
            query: query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )

        let response = server.respond(to: recorded)
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}
}

private extension URLRequest {
    /// `URLSession` converts an `httpBody` to `httpBodyStream` before a
    /// `URLProtocol` sees it, so a mock that only reads `httpBody` silently
    /// sees no body at all.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

/// Host-to-server map, so several mock servers can be live at once and tests
/// can run in parallel.
final class MockRegistry: @unchecked Sendable {
    static let shared = MockRegistry()

    /// Weak, so registering a server does not keep it alive past the end of the
    /// test that made it — a strong map here would mean `deinit` never runs and
    /// every test leaked its server.
    private final class WeakBox {
        weak var server: MockABSServer?
        init(_ server: MockABSServer) { self.server = server }
    }

    private let lock = NSLock()
    private var servers: [String: WeakBox] = [:]

    func register(_ server: MockABSServer, forHost host: String) {
        lock.withLock { servers[host] = WeakBox(server) }
    }

    func unregister(host: String) {
        lock.withLock { servers[host] = nil }
    }

    func server(forHost host: String) -> MockABSServer? {
        lock.withLock {
            guard let box = servers[host] else { return nil }
            guard let server = box.server else {
                servers[host] = nil
                return nil
            }
            return server
        }
    }
}
