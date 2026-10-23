import Foundation

/// Scrubbing for anything that might be logged, shown in an error, or included
/// in the diagnostics export.
///
/// Working rule 7 of the spec: never log or display tokens, passwords or full
/// server URLs. Everything that writes a diagnostic goes through here.
public enum Redaction {
    /// `https://books.example.com:8443/abs/api/libraries` -> `https://<server>/abs/api/libraries`
    ///
    /// The path survives because it is what makes a log useful; the host and
    /// port are what identify a user's private server.
    public static func url(_ url: URL?) -> String {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<url>"
        }
        let scheme = components.scheme ?? "https"
        var path = components.path
        if path.isEmpty { path = "/" }
        return "\(scheme)://<server>\(path)"
    }

    /// Keeps enough of a token to correlate two log lines, never enough to use it.
    public static func token(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "<none>" }
        return "<token:\(token.count)ch>"
    }

    /// Header values are redacted by default; only a small allowlist of
    /// non-identifying headers is printed in full.
    public static func headers(_ headers: [String: String]) -> [String: String] {
        let safeToPrint: Set<String> = ["accept", "content-type", "user-agent", "accept-encoding"]
        return headers.reduce(into: [:]) { result, pair in
            result[pair.key] = safeToPrint.contains(pair.key.lowercased()) ? pair.value : "<redacted>"
        }
    }

    public static func username(_ username: String?) -> String {
        guard let username, !username.isEmpty else { return "<none>" }
        return "<user:\(username.count)ch>"
    }
}
