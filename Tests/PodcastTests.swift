import Foundation
import Testing
@testable import ABSKit
@testable import Persistence

@Suite("Podcast decoding")
struct PodcastDecodingTests {
    /// The shape `PodcastEpisode.toOldJSONExpanded()` produces.
    private let episodeJSON = Data("""
    {"libraryItemId":"li-1","podcastId":"pod-1","id":"ep-1","oldEpisodeId":null,
     "index":14,"season":"2","episode":"14","episodeType":"full",
     "title":"The One About Testing","subtitle":"A subtitle","description":"<p>Notes</p>",
     "enclosure":{"url":"https://example.com/ep.mp3","type":"audio/mpeg","length":"48210000"},
     "guid":"abc","pubDate":"Mon, 01 Jan 2024 00:00:00 GMT",
     "chapters":[{"id":0,"start":0,"end":60,"title":"Intro"}],
     "publishedAt":1704067200000,"addedAt":1704067300000,"updatedAt":1704067300000,
     "audioTrack":{"index":1,"startOffset":0,"duration":2700.5,"title":"ep.mp3",
     "contentUrl":"/api/items/li-1/file/900","mimeType":"audio/mpeg","codec":"mp3"},
     "size":48210000,"duration":2700.5}
    """.utf8)

    @Test("Decodes an expanded episode, including the enclosure")
    func episode() throws {
        let episode = try ABSJSON.decoder.decode(ABSPodcastEpisode.self, from: episodeJSON)
        #expect(episode.id == "ep-1")
        #expect(episode.title == "The One About Testing")
        #expect(episode.duration == 2700.5)
        #expect(episode.publishedAt == Date(timeIntervalSince1970: 1_704_067_200))
        #expect(episode.enclosure?.type == "audio/mpeg")
        // ABS stringifies the byte length from a BigInt.
        #expect(episode.enclosure?.bytes == 48_210_000)
        #expect(episode.audioTrack?.contentUrl == "/api/items/li-1/file/900")
        #expect(episode.chapters?.first?.title == "Intro")
    }

    @Test("Numbering reads the way a podcast app shows it")
    func numbering() throws {
        let full = try ABSJSON.decoder.decode(ABSPodcastEpisode.self, from: episodeJSON)
        #expect(full.numbering == "S2E14")

        let noSeason = Data("""
        {"id":"e","episode":"7"}
        """.utf8)
        #expect(try ABSJSON.decoder.decode(ABSPodcastEpisode.self, from: noSeason).numbering == "Episode 7")

        let neither = Data("""
        {"id":"e"}
        """.utf8)
        #expect(try ABSJSON.decoder.decode(ABSPodcastEpisode.self, from: neither).numbering == nil)

        // Empty strings are what ABS actually sends for an absent number.
        let empty = Data("""
        {"id":"e","season":"","episode":""}
        """.utf8)
        #expect(try ABSJSON.decoder.decode(ABSPodcastEpisode.self, from: empty).numbering == nil)
    }

    @Test("Size falls back to the enclosure when the expanded form is absent")
    func sizeFallback() throws {
        let minified = Data("""
        {"id":"e","enclosure":{"url":"u","type":"audio/mpeg","length":"1234"}}
        """.utf8)
        let episode = try ABSJSON.decoder.decode(ABSPodcastEpisode.self, from: minified)
        #expect(episode.size == nil)
        #expect(episode.sizeBytes == 1234)
    }

    @Test("A podcast's media is a different shape from a book's")
    func podcastMedia() throws {
        // `author`, not `authorName` — decoding a podcast with the book model
        // silently loses it, which is the bug this type exists to prevent.
        let json = Data("""
        {"id":"li-1","libraryId":"lib-2","mediaType":"podcast","addedAt":1700000000000,
         "media":{"id":"pod-1","coverPath":"/c.jpg","numEpisodes":42,
         "autoDownloadEpisodes":true,"size":900,
         "metadata":{"title":"A Show","author":"A Host","description":"d",
         "feedUrl":"https://example.com/rss","explicit":false,"genres":["Tech"]}}}
        """.utf8)
        let item = try ABSJSON.decoder.decode(ABSPodcastItem.self, from: json)
        #expect(item.media?.metadata.title == "A Show")
        #expect(item.media?.metadata.author == "A Host")
        #expect(item.media?.numEpisodes == 42)
        #expect(item.media?.autoDownloadEpisodes == true)
        #expect(item.media?.episodes == nil, "the minified form carries no episodes")
    }

    @Test("Episodes only arrive on the expanded item")
    func expandedCarriesEpisodes() throws {
        let json = Data("""
        {"id":"li-1","mediaType":"podcast","media":{"metadata":{"title":"S"},
         "episodes":[{"id":"ep-1","title":"One"},{"id":"ep-2","title":"Two"}]}}
        """.utf8)
        let item = try ABSJSON.decoder.decode(ABSPodcastItem.self, from: json)
        #expect(item.media?.episodes?.count == 2)
    }

    @Test("The expanded request is what asks for them")
    func expandedEndpoint() {
        let request = ABSEndpoint.podcast(itemID: "li-1")
        #expect(request.query.contains { $0.name == "expanded" && $0.value == "1" })
    }
}

@Suite("Up Next queue")
struct QueueEntryTests {
    @Test("A book and an episode of the same show are different entries")
    func identity() {
        let book = QueueEntry(itemID: "li-1", title: "A Book")
        let episode = QueueEntry(itemID: "li-1", episodeID: "ep-1", title: "An Episode")
        #expect(book.id == "li-1")
        #expect(episode.id == "li-1/ep-1")
        #expect(book.id != episode.id)
    }

    @Test("Two episodes of one show are distinct")
    func episodesAreDistinct() {
        let first = QueueEntry(itemID: "li-1", episodeID: "ep-1", title: "One")
        let second = QueueEntry(itemID: "li-1", episodeID: "ep-2", title: "Two")
        #expect(first.id != second.id)
    }

    @Test("Survives the trip through the shared container")
    func codable() throws {
        let entries = [
            QueueEntry(itemID: "li-1", title: "A Book"),
            QueueEntry(itemID: "li-2", episodeID: "ep-9", title: "An Episode", subtitle: "A Show"),
        ]
        let data = try JSONEncoder().encode(entries)
        #expect(try JSONDecoder().decode([QueueEntry].self, from: data) == entries)
    }
}

@Suite("Episode summary")
struct EpisodeSummaryTests {
    private func summary(fraction: Double, finished: Bool) -> EpisodeSummary {
        EpisodeSummary(
            id: "x", itemID: "li-1", episodeID: "ep-1", title: "T", subtitle: nil,
            summary: nil, numbering: nil, duration: 3600, sizeBytes: 0, publishedAt: nil,
            progressCurrentTime: 3600 * fraction, progressFraction: fraction, isFinished: finished
        )
    }

    @Test("Unplayed, in progress and finished are mutually exclusive")
    func states() {
        let fresh = summary(fraction: 0, finished: false)
        #expect(fresh.isUnplayed)
        #expect(!fresh.isStarted)

        let started = summary(fraction: 0.4, finished: false)
        #expect(started.isStarted)
        #expect(!started.isUnplayed)

        let done = summary(fraction: 1, finished: true)
        #expect(!done.isStarted)
        #expect(!done.isUnplayed)
    }

    @Test("Remaining time counts down")
    func remaining() {
        #expect(summary(fraction: 0.25, finished: false).remainingTime == 2700)
    }
}
