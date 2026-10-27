import Foundation
import Testing
@testable import DownloadKit

@Suite("Preparing a download to share")
struct SharedDownloadTests {
    @Test("A single file takes the book's own name")
    func singleFileIsJustTheTitle() {
        #expect(SharedDownload.fileName(
            title: "Alice's Adventures in Wonderland", index: 0, of: 1, extension: "m4b"
        ) == "Alice's Adventures in Wonderland.m4b")
    }

    @Test("Several files are numbered so they sort in reading order")
    func severalFilesAreNumbered() {
        let names = (0..<3).map {
            SharedDownload.fileName(title: "Dracula", index: $0, of: 3, extension: "m4a")
        }
        #expect(names == [
            "Dracula 1 of 3.m4a",
            "Dracula 2 of 3.m4a",
            "Dracula 3 of 3.m4a",
        ])
    }

    @Test("Numbering is padded so ten files still sort correctly")
    func numberingIsPadded() {
        let first = SharedDownload.fileName(title: "Moby Dick", index: 0, of: 12, extension: "m4a")
        let tenth = SharedDownload.fileName(title: "Moby Dick", index: 9, of: 12, extension: "m4a")
        #expect(first == "Moby Dick 01 of 12.m4a")
        #expect(tenth == "Moby Dick 10 of 12.m4a")
        // The point of the padding: plain sorting puts them in order.
        #expect([tenth, first].sorted() == [first, tenth])
    }

    @Test("Characters a file system cannot take are removed")
    func sanitisesTheTitle() {
        #expect(SharedDownload.sanitised("20,000 Leagues: Under/the Sea") == "20,000 Leagues Under the Sea")
        #expect(SharedDownload.sanitised("What?*Is|This") == "What Is This")
    }

    @Test("A title that is only punctuation still produces a usable name")
    func fallsBackWhenNothingSurvives() {
        #expect(SharedDownload.sanitised("///") == "Audiobook")
        #expect(SharedDownload.sanitised("   ") == "Audiobook")
        #expect(SharedDownload.sanitised("") == "Audiobook")
    }

    @Test("A leading dot is stripped so the file is not hidden")
    func stripsLeadingDots() {
        #expect(SharedDownload.sanitised(".hidden") == "hidden")
        #expect(SharedDownload.sanitised("..Dracula") == "Dracula")
    }

    @Test("An absurdly long title is cut to something a file system takes")
    func trimsVeryLongTitles() {
        let long = String(repeating: "a", count: 400)
        #expect(SharedDownload.sanitised(long).count == 120)
    }

    @Test("Staging copies the files under readable names, leaving the originals")
    func stagesReadableCopies() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "firelight-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Named the way downloads actually are: the server's inode number.
        let sources = try ["9472913.m4a", "9472914.m4a"].map { name -> URL in
            let url = scratch.appending(path: name)
            try Data("audio".utf8).write(to: url)
            return url
        }

        let staged = try SharedDownload.stage(title: "Dracula", sources: sources)
        defer { SharedDownload.clearStaged() }

        #expect(staged.map(\.lastPathComponent) == ["Dracula 1 of 2.m4a", "Dracula 2 of 2.m4a"])
        for url in staged {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        // The originals are where playback still expects them.
        for url in sources {
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("A file with no extension still gets a playable one")
    func defaultsTheExtension() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "firelight-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let source = scratch.appending(path: "9472913")
        try Data("audio".utf8).write(to: source)

        let staged = try SharedDownload.stage(title: "Dracula", sources: [source])
        defer { SharedDownload.clearStaged() }
        #expect(staged.first?.lastPathComponent == "Dracula.m4b")
    }

    @Test("Nothing to share stages nothing rather than an empty folder")
    func emptyInput() throws {
        #expect(try SharedDownload.stage(title: "Dracula", sources: []).isEmpty)
    }

    @Test("Clearing removes everything staged")
    func clearingRemovesStaged() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "firelight-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let source = scratch.appending(path: "1.m4a")
        try Data("audio".utf8).write(to: source)

        let staged = try SharedDownload.stage(title: "Dracula", sources: [source])
        SharedDownload.clearStaged()
        for url in staged {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }
}
