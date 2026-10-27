import Foundation

/// A typed front door to one Audiobookshelf server.
///
/// Holds no state beyond its transport: the token lives in the
/// `AccessTokenProviding` the client was built with, and the server's feature
/// table is derived from whatever `status()` last returned. Inject it; never
/// reach for a singleton.
public struct ABSClient: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    /// Server identity and version. Works before sign-in, and is what the
    /// onboarding connection check calls.
    public func status() async throws -> ServerStatus {
        try await http.send(ABSEndpoint.status(), decoding: ServerStatus.self)
    }

    /// Cheap reachability check. Returns false rather than throwing for any
    /// answer that isn't a healthy ping, because callers race it across
    /// addresses and only care which one answers.
    public func ping() async -> Bool {
        do {
            let response = try await http.send(ABSEndpoint.ping())
            return response.isSuccess
        } catch {
            return false
        }
    }

    public func login(username: String, password: String) async throws -> LoginResponse {
        try await http.send(try ABSEndpoint.login(username: username, password: password), decoding: LoginResponse.self)
    }

    /// Creates an account for an invitation. Admin only.
    public func createUser(username: String, password: String) async throws -> ABSUser {
        try await http.send(
            try ABSEndpoint.createUser(username: username, password: password),
            decoding: CreatedUserResponse.self
        ).user
    }

    /// Replaces the signed-in account's own password and returns the tokens
    /// that survive it.
    ///
    /// Audiobookshelf invalidates every other session for the account when a
    /// password changes — which is the property that makes a redeemed
    /// invitation a spent match — so the caller must store what comes back or
    /// find itself signed out.
    public func changeOwnPassword(current: String, new: String) async throws -> LoginResponse {
        try await http.send(
            try ABSEndpoint.changeOwnPassword(current: current, new: new),
            decoding: LoginResponse.self
        )
    }

    public func refresh(refreshToken: String) async throws -> LoginResponse {
        try await http.send(ABSEndpoint.refresh(refreshToken: refreshToken), decoding: LoginResponse.self)
    }

    public func logout(refreshToken: String?) async throws {
        try await http.send(ignoringBody: ABSEndpoint.logout(refreshToken: refreshToken))
    }

    /// Completes an OpenID Connect sign-in. Returns the same payload as login.
    public func completeOpenIDSignIn(code: String, state: String, codeVerifier: String) async throws -> LoginResponse {
        try await http.send(
            ABSEndpoint.openIDCallback(code: code, state: state, codeVerifier: codeVerifier),
            decoding: LoginResponse.self
        )
    }

    public func me() async throws -> ABSUser {
        try await http.send(ABSEndpoint.me(), decoding: ABSUser.self)
    }

    /// The signed-in user with their progress for every item.
    public func myProgress() async throws -> [ABSMediaProgress] {
        try await http.send(ABSEndpoint.me(), decoding: ABSMe.self).mediaProgress ?? []
    }

    // MARK: - Library

    public func libraries() async throws -> [ABSLibrary] {
        try await http.send(ABSEndpoint.libraries(), decoding: ABSLibrariesResponse.self).libraries
    }

    public func libraryItems(
        libraryID: String,
        limit: Int = 100,
        page: Int = 0,
        sort: String? = nil,
        descending: Bool = false,
        filter: String? = nil
    ) async throws -> ABSLibraryItemsPage {
        try await http.send(
            ABSEndpoint.libraryItems(
                libraryID: libraryID,
                limit: limit,
                page: page,
                sort: sort,
                descending: descending,
                filter: filter
            ),
            decoding: ABSLibraryItemsPage.self
        )
    }

    /// Walks every page of a library. `onPage` is called as each arrives so a
    /// first sync can show progress instead of a spinner that never moves.
    public func allLibraryItems(
        libraryID: String,
        pageSize: Int = 200,
        onPage: (@Sendable ([ABSLibraryItem], Int?) -> Void)? = nil
    ) async throws -> [ABSLibraryItem] {
        var collected: [ABSLibraryItem] = []
        var page = 0
        while true {
            let result = try await libraryItems(libraryID: libraryID, limit: pageSize, page: page)
            collected.append(contentsOf: result.results)
            onPage?(result.results, result.total)
            // Stop on a short page: `total` is absent on some paths, so it
            // cannot be the only termination condition.
            if result.results.count < pageSize { break }
            if let total = result.total, collected.count >= total { break }
            page += 1
            if page > 500 { break } // 100k items; a guard against a server that never shortens a page.
        }
        return collected
    }

    public func series(libraryID: String, limit: Int = 200, page: Int = 0) async throws -> [ABSSeries] {
        try await http.send(
            ABSEndpoint.librarySeries(libraryID: libraryID, limit: limit, page: page),
            decoding: ABSSeriesPage.self
        ).results
    }

    public func search(libraryID: String, query: String, limit: Int = 20) async throws -> ABSSearchResults {
        try await http.send(
            ABSEndpoint.librarySearch(libraryID: libraryID, query: query, limit: limit),
            decoding: ABSSearchResults.self
        )
    }

    public func item(id: String, expanded: Bool = false) async throws -> ABSLibraryItem {
        try await http.send(ABSEndpoint.item(id: id, expanded: expanded), decoding: ABSLibraryItem.self)
    }

    /// Fetches an ebook and writes it to `destination`.
    ///
    /// Returned as a file rather than data: an EPUB can be hundreds of
    /// megabytes, and Readium wants a URL anyway.
    public func downloadEbook(itemID: String, fileID: String? = nil, to destination: URL) async throws -> URL {
        let response = try await http.send(ABSEndpoint.ebookFile(itemID: itemID, fileID: fileID))
        guard response.isSuccess else {
            throw APIError.server(status: response.status, message: nil)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try response.body.write(to: destination, options: .atomic)
        return destination
    }

    // MARK: - Admin

    public func librariesWithFolders() async throws -> [ABSLibraryWithFolders] {
        try await http.send(
            ABSEndpoint.librariesWithFolders(), decoding: ABSLibrariesWithFoldersResponse.self
        ).libraries
    }

    public func scanLibrary(libraryID: String, force: Bool = false) async throws {
        try await http.send(ignoringBody: ABSEndpoint.scanLibrary(libraryID: libraryID, force: force))
    }

    public func tasks() async throws -> [ABSTask] {
        try await http.send(ABSEndpoint.tasks(), decoding: ABSTasksResponse.self).tasks
    }

    public func users() async throws -> [ABSAdminUser] {
        try await http.send(ABSEndpoint.users(), decoding: ABSUsersResponse.self).users
    }

    public func listeningSessions(limit: Int = 25) async throws -> [ABSListeningSession] {
        try await http.send(
            ABSEndpoint.listeningSessions(limit: limit), decoding: ABSSessionsResponse.self
        ).sessions ?? []
    }

    public func updateMetadata(itemID: String, metadata: [String: String]) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.updateMedia(itemID: itemID, metadata: metadata))
    }

    /// Uploads files into a library folder. Needs the `canUpload` permission,
    /// which the server checks before anything else.
    public func upload(_ request: UploadRequest) async throws {
        try await http.send(ignoringBody: ABSEndpoint.upload(request))
    }

    // MARK: - Podcasts

    public func podcastItems(libraryID: String, limit: Int = 100, page: Int = 0) async throws -> [ABSPodcastItem] {
        try await http.send(
            ABSEndpoint.libraryItems(libraryID: libraryID, limit: limit, page: page),
            decoding: ABSPodcastItemsPage.self
        ).results
    }

    /// The show page: metadata plus every episode.
    public func podcast(itemID: String) async throws -> ABSPodcastItem {
        try await http.send(ABSEndpoint.podcast(itemID: itemID), decoding: ABSPodcastItem.self)
    }

    public func recentEpisodes(libraryID: String, limit: Int = 50) async throws -> [ABSPodcastEpisode] {
        try await http.send(
            ABSEndpoint.recentEpisodes(libraryID: libraryID, limit: limit),
            decoding: ABSRecentEpisodesPage.self
        ).episodes ?? []
    }

    public func setPodcastAutoDownload(itemID: String, enabled: Bool) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.setAutoDownload(itemID: itemID, enabled: enabled))
    }

    @discardableResult
    public func checkForNewEpisodes(itemID: String) async throws -> HTTPResponse {
        try await http.send(ABSEndpoint.checkForNewEpisodes(itemID: itemID))
    }

    // MARK: - Playback

    public func openPlaybackSession(
        itemID: String,
        episodeID: String? = nil,
        request: PlaybackSessionRequest
    ) async throws -> ABSPlaybackSession {
        try await http.send(
            try ABSEndpoint.play(itemID: itemID, episodeID: episodeID, request: request),
            decoding: ABSPlaybackSession.self
        )
    }

    public func syncSession(id: String, currentTime: Double, timeListened: Double, duration: Double) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.syncSession(
            id: id,
            currentTime: currentTime,
            timeListened: timeListened,
            duration: duration
        ))
    }

    public func closeSession(id: String, currentTime: Double?, timeListened: Double?, duration: Double?) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.closeSession(
            id: id,
            currentTime: currentTime,
            timeListened: timeListened,
            duration: duration
        ))
    }

    public func syncLocalSession(_ session: LocalPlaybackSession) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.syncLocalSession(session))
    }

    public func syncLocalSessions(_ sessions: [LocalPlaybackSession]) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.syncLocalSessions(sessions))
    }

    public func updateProgress(
        itemID: String,
        episodeID: String? = nil,
        currentTime: Double? = nil,
        duration: Double? = nil,
        progress: Double? = nil,
        isFinished: Bool? = nil,
        ebookLocation: String? = nil,
        ebookProgress: Double? = nil
    ) async throws {
        try await http.send(ignoringBody: try ABSEndpoint.updateProgress(
            itemID: itemID,
            episodeID: episodeID,
            currentTime: currentTime,
            duration: duration,
            progress: progress,
            isFinished: isFinished,
            ebookLocation: ebookLocation,
            ebookProgress: ebookProgress
        ))
    }

    // MARK: - Bookmarks

    public func bookmarks(itemID: String) async throws -> [ABSBookmark] {
        try await http.send(ABSEndpoint.bookmarks(itemID: itemID), decoding: [ABSBookmark].self)
    }

    @discardableResult
    public func createBookmark(itemID: String, time: Double, title: String) async throws -> ABSBookmark {
        try await http.send(
            try ABSEndpoint.createBookmark(itemID: itemID, time: time, title: title),
            decoding: ABSBookmark.self
        )
    }

    @discardableResult
    public func updateBookmark(itemID: String, time: Double, title: String) async throws -> ABSBookmark {
        try await http.send(
            try ABSEndpoint.updateBookmark(itemID: itemID, time: time, title: title),
            decoding: ABSBookmark.self
        )
    }

    public func deleteBookmark(itemID: String, time: Double) async throws {
        try await http.send(ignoringBody: ABSEndpoint.deleteBookmark(itemID: itemID, time: time))
    }
}
