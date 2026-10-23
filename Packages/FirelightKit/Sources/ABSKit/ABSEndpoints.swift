import Foundation

/// The Audiobookshelf calls Firelight makes, one factory per endpoint.
///
/// Every entry here was checked against the ABS source (`server/Server.js`,
/// `server/Auth.js`, `server/routers/ApiRouter.js`) — see the route table in
/// CLAUDE.md. Endpoints are added in the phase that uses them, so that nothing
/// in this file is a guess.
public enum ABSEndpoint {
    // MARK: - Unauthenticated (registered on the root router, not under /api)

    /// Server identity, version and configured auth methods.
    public static func status() -> HTTPRequest {
        HTTPRequest(path: "/status", requiresAuth: false, retriesAfterTokenRefresh: false)
    }

    /// `{ "success": true }`. The cheapest reachability check there is, which
    /// makes it the right call for the home/away address race.
    public static func ping() -> HTTPRequest {
        HTTPRequest(path: "/ping", requiresAuth: false, retriesAfterTokenRefresh: false)
    }

    /// Password sign-in.
    ///
    /// `x-return-tokens: true` is what puts the refresh token in the response
    /// body; without it ABS sets an http-only cookie instead, which is no use
    /// to a native client that wants the token in the Keychain.
    public static func login(username: String, password: String) throws -> HTTPRequest {
        struct Body: Encodable {
            let username: String
            let password: String
        }
        return HTTPRequest(
            method: .post,
            path: "/login",
            headers: ["x-return-tokens": "true"],
            body: try ABSJSON.encoder.encode(Body(username: username, password: password)),
            requiresAuth: false,
            retriesAfterTokenRefresh: false
        )
    }

    /// Exchanges a refresh token for a new access token.
    ///
    /// The token goes in `x-refresh-token`, never in the body: ABS reads the
    /// cookie first and lets this header override it, and sending the header is
    /// also what makes the new refresh token come back in the response.
    public static func refresh(refreshToken: String) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            path: "/auth/refresh",
            headers: ["x-refresh-token": refreshToken],
            requiresAuth: false,
            retriesAfterTokenRefresh: false
        )
    }

    /// Invalidates the refresh token server-side.
    public static func logout(refreshToken: String?) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            path: "/logout",
            headers: refreshToken.map { ["x-refresh-token": $0] } ?? [:],
            requiresAuth: true,
            retriesAfterTokenRefresh: false
        )
    }

    // MARK: - OpenID Connect

    /// The URL to open in `ASWebAuthenticationSession` to begin SSO.
    ///
    /// Verified against `OidcAuthStrategy`: any of `response_type=code`,
    /// `redirect_uri` or `code_challenge` marks this as the mobile flow, which
    /// is the one that returns tokens as JSON instead of cookies.
    /// `code_challenge` is required and `code_challenge_method` must be `S256`.
    ///
    /// The `redirectURI` must be whitelisted in the server's
    /// "Mobile redirect URIs" auth setting, or ABS rejects the request — there
    /// is no scheme pattern matching, only exact matches (or a lone `*`).
    public static func openIDAuthorizationURL(
        baseURL: URL,
        redirectURI: String,
        pkce: PKCEPair,
        state: String
    ) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appending(path: "auth/openid"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url
    }

    /// Redeems the authorisation code for tokens.
    ///
    /// The app makes this call itself, after the browser hands back `code` and
    /// `state`. ABS tracks the mobile flow in a server-side map keyed by
    /// `state`, so no browser cookie is needed here. The response is the same
    /// payload as `/login`.
    public static func openIDCallback(code: String, state: String, codeVerifier: String) -> HTTPRequest {
        HTTPRequest(
            path: "/auth/openid/callback",
            query: [
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_verifier", value: codeVerifier),
            ],
            requiresAuth: false,
            retriesAfterTokenRefresh: false
        )
    }

    // MARK: - Authenticated (under /api)

    /// The signed-in user, including media progress and bookmarks.
    public static func me() -> HTTPRequest {
        HTTPRequest(path: "/api/me")
    }

    // MARK: - Library

    public static func libraries() -> HTTPRequest {
        HTTPRequest(path: "/api/libraries")
    }

    /// One page of a library's items.
    ///
    /// `limit` and `page` must be non-negative integers or ABS answers 400.
    /// `minified=1` is what keeps a 5,000-book library from being a 40 MB
    /// response.
    public static func libraryItems(
        libraryID: String,
        limit: Int = 100,
        page: Int = 0,
        sort: String? = nil,
        descending: Bool = false,
        filter: String? = nil,
        collapseSeries: Bool = false,
        minified: Bool = true
    ) -> HTTPRequest {
        var query = [
            URLQueryItem(name: "limit", value: String(max(0, limit))),
            URLQueryItem(name: "page", value: String(max(0, page))),
        ]
        if minified { query.append(URLQueryItem(name: "minified", value: "1")) }
        if let sort { query.append(URLQueryItem(name: "sort", value: sort)) }
        if descending { query.append(URLQueryItem(name: "desc", value: "1")) }
        if let filter { query.append(URLQueryItem(name: "filter", value: filter)) }
        if collapseSeries { query.append(URLQueryItem(name: "collapseseries", value: "1")) }
        return HTTPRequest(path: "/api/libraries/\(libraryID)/items", query: query)
    }

    public static func librarySeries(libraryID: String, limit: Int = 100, page: Int = 0) -> HTTPRequest {
        HTTPRequest(
            path: "/api/libraries/\(libraryID)/series",
            query: [
                URLQueryItem(name: "limit", value: String(max(0, limit))),
                URLQueryItem(name: "page", value: String(max(0, page))),
            ]
        )
    }

    /// Server-side search within one library. Firelight searches its own cache
    /// first and only falls back to this, so results appear offline too.
    public static func librarySearch(libraryID: String, query: String, limit: Int = 20) -> HTTPRequest {
        HTTPRequest(
            path: "/api/libraries/\(libraryID)/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(max(1, limit))),
            ]
        )
    }

    public static func item(id: String, expanded: Bool = false) -> HTTPRequest {
        HTTPRequest(
            path: "/api/items/\(id)",
            query: expanded ? [URLQueryItem(name: "expanded", value: "1")] : []
        )
    }

    // MARK: - Admin

    /// Libraries including their folders, which an upload needs.
    public static func librariesWithFolders() -> HTTPRequest {
        HTTPRequest(path: "/api/libraries")
    }

    public static func scanLibrary(libraryID: String, force: Bool = false) -> HTTPRequest {
        HTTPRequest(
            method: .post,
            path: "/api/libraries/\(libraryID)/scan",
            query: force ? [URLQueryItem(name: "force", value: "1")] : []
        )
    }

    /// Running and recent background jobs, which is how scan progress is seen.
    public static func tasks() -> HTTPRequest {
        HTTPRequest(path: "/api/tasks")
    }

    public static func users() -> HTTPRequest {
        HTTPRequest(path: "/api/users")
    }

    public static func onlineUsers() -> HTTPRequest {
        HTTPRequest(path: "/api/users/online")
    }

    public static func listeningSessions(limit: Int = 25) -> HTTPRequest {
        HTTPRequest(
            path: "/api/sessions",
            query: [URLQueryItem(name: "itemsPerPage", value: String(limit))]
        )
    }

    /// Looks the item up with the server's metadata providers.
    public static func matchItem(itemID: String, provider: String?, title: String?, author: String?) throws -> HTTPRequest {
        struct Body: Encodable {
            let provider: String?
            let title: String?
            let author: String?
        }
        return HTTPRequest(
            method: .post,
            path: "/api/items/\(itemID)/match",
            body: try ABSJSON.encoder.encode(Body(provider: provider, title: title, author: author))
        )
    }

    /// Edits an item's metadata.
    public static func updateMedia(itemID: String, metadata: [String: String]) throws -> HTTPRequest {
        struct Body: Encodable {
            let metadata: [String: String]
        }
        return HTTPRequest(
            method: .patch,
            path: "/api/items/\(itemID)/media",
            body: try ABSJSON.encoder.encode(Body(metadata: metadata))
        )
    }

    /// Multipart upload. Verified against `MiscController.handleUpload`.
    public static func upload(_ request: UploadRequest) -> HTTPRequest {
        let boundary = MultipartBody.newBoundary()
        return HTTPRequest(
            method: .post,
            path: "/api/upload",
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: MultipartBody.make(boundary: boundary, request: request)
        )
    }

    // MARK: - Podcasts

    /// Episodes come back only on the expanded item, so a show page needs
    /// `expanded=1` — the minified form carries `numEpisodes` and nothing else.
    public static func podcast(itemID: String) -> HTTPRequest {
        HTTPRequest(path: "/api/items/\(itemID)", query: [URLQueryItem(name: "expanded", value: "1")])
    }

    public static func podcastEpisode(itemID: String, episodeID: String) -> HTTPRequest {
        HTTPRequest(path: "/api/podcasts/\(itemID)/episode/\(episodeID)")
    }

    /// Newest episodes across a whole podcast library.
    public static func recentEpisodes(libraryID: String, limit: Int = 50, page: Int = 0) -> HTTPRequest {
        HTTPRequest(
            path: "/api/libraries/\(libraryID)/recent-episodes",
            query: [
                URLQueryItem(name: "limit", value: String(max(1, limit))),
                URLQueryItem(name: "page", value: String(max(0, page))),
            ]
        )
    }

    /// Asks the **server** to download episodes into the library. This is not
    /// the same as downloading to the device — it is how ABS fetches an
    /// episode from the feed in the first place.
    public static func downloadEpisodesToServer(itemID: String, episodes: [ABSPodcastEpisode]) throws -> HTTPRequest {
        HTTPRequest(
            method: .post,
            path: "/api/podcasts/\(itemID)/download-episodes",
            body: try ABSJSON.encoder.encode(episodes)
        )
    }

    /// Checks the feed for anything new.
    public static func checkForNewEpisodes(itemID: String) -> HTTPRequest {
        HTTPRequest(path: "/api/podcasts/\(itemID)/checknew")
    }

    /// Turns the server's own auto-download on or off for one show.
    public static func setAutoDownload(itemID: String, enabled: Bool) throws -> HTTPRequest {
        struct Body: Encodable {
            let autoDownloadEpisodes: Bool
        }
        return HTTPRequest(
            method: .patch,
            path: "/api/items/\(itemID)/media",
            body: try ABSJSON.encoder.encode(Body(autoDownloadEpisodes: enabled))
        )
    }

    // MARK: - Playback

    /// Opens a playback session. ABS answers with the audio tracks, the
    /// chapters and where it thinks the listener is.
    public static func play(itemID: String, episodeID: String? = nil, request: PlaybackSessionRequest) throws -> HTTPRequest {
        let path = episodeID.map { "/api/items/\(itemID)/play/\($0)" } ?? "/api/items/\(itemID)/play"
        return HTTPRequest(method: .post, path: path, body: try ABSJSON.encoder.encode(request))
    }

    /// Reports progress into an open session.
    public static func syncSession(id: String, currentTime: Double, timeListened: Double, duration: Double) throws -> HTTPRequest {
        struct Body: Encodable {
            let currentTime: Double
            let timeListened: Double
            let duration: Double
        }
        return HTTPRequest(
            method: .post,
            path: "/api/session/\(id)/sync",
            body: try ABSJSON.encoder.encode(
                Body(currentTime: currentTime, timeListened: timeListened, duration: duration)
            )
        )
    }

    public static func closeSession(id: String, currentTime: Double?, timeListened: Double?, duration: Double?) throws -> HTTPRequest {
        struct Body: Encodable {
            let currentTime: Double?
            let timeListened: Double?
            let duration: Double?
        }
        return HTTPRequest(
            method: .post,
            path: "/api/session/\(id)/close",
            body: try ABSJSON.encoder.encode(
                Body(currentTime: currentTime, timeListened: timeListened, duration: duration)
            )
        )
    }

    /// Reports a listen that happened offline.
    ///
    /// ABS answers 200 with an empty body, so there is nothing to decode.
    public static func syncLocalSession(_ session: LocalPlaybackSession) throws -> HTTPRequest {
        HTTPRequest(
            method: .post,
            path: "/api/session/local",
            body: try ABSJSON.encoder.encode(session)
        )
    }

    /// The batch form, for draining a queue after a long time offline.
    public static func syncLocalSessions(_ sessions: [LocalPlaybackSession]) throws -> HTTPRequest {
        struct Body: Encodable { let sessions: [LocalPlaybackSession] }
        return HTTPRequest(
            method: .post,
            path: "/api/session/local-all",
            body: try ABSJSON.encoder.encode(Body(sessions: sessions))
        )
    }

    /// Writes a position straight onto the user's media progress.
    ///
    /// The episode id is part of the *path*, not the body.
    public static func updateProgress(
        itemID: String,
        episodeID: String?,
        currentTime: Double?,
        duration: Double?,
        progress: Double?,
        isFinished: Bool?,
        ebookLocation: String?,
        ebookProgress: Double?
    ) throws -> HTTPRequest {
        struct Body: Encodable {
            let currentTime: Double?
            let duration: Double?
            let progress: Double?
            let isFinished: Bool?
            let ebookLocation: String?
            let ebookProgress: Double?
        }
        let path = episodeID.map { "/api/me/progress/\(itemID)/\($0)" } ?? "/api/me/progress/\(itemID)"
        return HTTPRequest(
            method: .patch,
            path: path,
            body: try ABSJSON.encoder.encode(Body(
                currentTime: currentTime,
                duration: duration,
                progress: progress,
                isFinished: isFinished,
                ebookLocation: ebookLocation,
                ebookProgress: ebookProgress
            ))
        )
    }

    // MARK: - Bookmarks

    public static func createBookmark(itemID: String, time: Double, title: String) throws -> HTTPRequest {
        struct Body: Encodable {
            let time: Int
            let title: String
        }
        return HTTPRequest(
            method: .post,
            path: "/api/me/item/\(itemID)/bookmark",
            body: try ABSJSON.encoder.encode(Body(time: Int(time.rounded()), title: title))
        )
    }

    public static func updateBookmark(itemID: String, time: Double, title: String) throws -> HTTPRequest {
        struct Body: Encodable {
            let time: Int
            let title: String
        }
        return HTTPRequest(
            method: .patch,
            path: "/api/me/item/\(itemID)/bookmark",
            body: try ABSJSON.encoder.encode(Body(time: Int(time.rounded()), title: title))
        )
    }

    /// The time is part of the path, so it must be the whole second ABS stored.
    public static func deleteBookmark(itemID: String, time: Double) -> HTTPRequest {
        HTTPRequest(method: .delete, path: "/api/me/item/\(itemID)/bookmark/\(Int(time.rounded()))")
    }

    public static func bookmarks(itemID: String) -> HTTPRequest {
        HTTPRequest(path: "/api/me/bookmarks/\(itemID)")
    }

    /// Downloads an ebook file. `fileID` is optional: without it ABS serves
    /// the item's primary ebook.
    public static func ebookFile(itemID: String, fileID: String?) -> HTTPRequest {
        let path = fileID.map { "/api/items/\(itemID)/ebook/\($0)" } ?? "/api/items/\(itemID)/ebook"
        return HTTPRequest(path: path)
    }

    /// The cover image path. Not an `HTTPRequest` because images are fetched by
    /// the image pipeline, which needs a URL — see `CoverImageLoader`.
    public static func coverPath(itemID: String) -> String {
        "/api/items/\(itemID)/cover"
    }

    /// Turns a track's relative `contentUrl` into something `AVPlayer` can open.
    ///
    /// The token goes in the query string because `AVPlayer` cannot set an
    /// `Authorization` header through public API, and ABS accepts
    /// `?token=` (`ExtractJwt.fromUrlQueryParameter`). `Redaction.url` drops
    /// query strings, so this never reaches a log.
    public static func mediaURL(baseURL: URL, contentPath: String, accessToken: String?) -> URL? {
        let relative = contentPath.hasPrefix("/") ? String(contentPath.dropFirst()) : contentPath
        guard var components = URLComponents(
            url: baseURL.appending(path: relative),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        if let accessToken {
            components.queryItems = [URLQueryItem(name: "token", value: accessToken)]
        }
        return components.url
    }
}
