import Foundation

/// Marks books as reading or finished on Hardcover.
///
/// Entirely optional and entirely the user's: they paste their own token, it
/// lives in the Keychain, and nothing is sent anywhere until they turn it on.
///
/// The endpoint and the `Authorization: Bearer` header are confirmed. **The
/// `status_id` values are not** — they come from community documentation, not
/// Hardcover's own, so they are named here in one place and should be checked
/// against a real account before anyone relies on them.
public struct HardcoverClient: Sendable {
    public enum Status: Int, Sendable, Hashable, CaseIterable {
        case wantToRead = 1
        case currentlyReading = 2
        case read = 3
        /// Listed by community docs; not confirmed.
        case paused = 4
        case didNotFinish = 5

        public var displayName: String {
            switch self {
            case .wantToRead: "Want to read"
            case .currentlyReading: "Currently reading"
            case .read: "Read"
            case .paused: "Paused"
            case .didNotFinish: "Did not finish"
            }
        }
    }

    public static let endpoint = URL(string: "https://api.hardcover.app/v1/graphql")!

    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        // A token pasted from the settings page may already carry the prefix.
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = trimmed.lowercased().hasPrefix("bearer ")
            ? String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            : trimmed
        self.session = session
    }

    public enum HardcoverError: Error, LocalizedError, Equatable {
        case noToken
        case unauthorized
        case notFound
        case transport(String)
        case graphQL(String)

        public var errorDescription: String? {
            switch self {
            case .noToken: "Add your Hardcover token in Settings first."
            case .unauthorized: "Hardcover rejected that token. It may have expired — they last a year."
            case .notFound: "Hardcover doesn't have that book."
            case .transport: "Couldn't reach Hardcover."
            case .graphQL(let message): message
            }
        }
    }

    /// Confirms the token works, and returns the account it belongs to.
    public func currentUser() async throws -> (id: Int, username: String) {
        let json = try await perform(query: "query { me { id username } }", variables: [:])
        // `me` is an array in Hasura's shaping of this schema.
        guard let me = (json["me"] as? [[String: Any]])?.first ?? (json["me"] as? [String: Any]),
              let id = me["id"] as? Int
        else { throw HardcoverError.notFound }
        return (id, me["username"] as? String ?? "")
    }

    /// Finds a book by title and author, so a shelf entry can be matched.
    public func findBook(title: String, author: String?) async throws -> Int? {
        let query = """
        query Search($q: String!) {
          search(query: $q, query_type: "Book", per_page: 5) { results }
        }
        """
        let json = try await perform(query: query, variables: ["q": [title, author].compactMap { $0 }.joined(separator: " ")])
        guard let search = json["search"] as? [String: Any],
              let results = search["results"] as? [String: Any],
              let hits = results["hits"] as? [[String: Any]],
              let first = hits.first,
              let document = first["document"] as? [String: Any]
        else { return nil }
        if let id = document["id"] as? Int { return id }
        if let idString = document["id"] as? String { return Int(idString) }
        return nil
    }

    /// Sets a book's status on the user's shelf.
    @discardableResult
    public func setStatus(bookID: Int, status: Status) async throws -> Bool {
        let mutation = """
        mutation SetStatus($bookId: Int!, $statusId: Int!) {
          insert_user_book(object: {book_id: $bookId, status_id: $statusId}) { id }
        }
        """
        let json = try await perform(
            query: mutation,
            variables: ["bookId": bookID, "statusId": status.rawValue]
        )
        return json["insert_user_book"] != nil
    }

    // MARK: - Transport

    private func perform(query: String, variables: [String: Any]) async throws -> [String: Any] {
        guard !token.isEmpty else { throw HardcoverError.noToken }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables]
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HardcoverError.transport(String(describing: type(of: error)))
        }

        if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
            throw HardcoverError.unauthorized
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HardcoverError.graphQL("Hardcover sent something unreadable.")
        }
        if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
            throw HardcoverError.graphQL(first["message"] as? String ?? "Hardcover returned an error.")
        }
        return json["data"] as? [String: Any] ?? [:]
    }

    /// Where the token lives. Never in a file, never in a log.
    public static func storedToken(keychain: KeychainStore = KeychainStore()) -> String? {
        try? keychain.string(for: "hardcover.token") ?? nil
    }

    public static func store(token: String?, keychain: KeychainStore = KeychainStore()) throws {
        if let token, !token.isEmpty {
            try keychain.setString(token, for: "hardcover.token")
        } else {
            try keychain.remove("hardcover.token")
        }
    }
}
