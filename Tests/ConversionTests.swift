import Foundation
import Testing
@testable import ConversionKit

/// Builds the first kilobyte of a PalmDB the way a real MOBI lays it out.
private func mobiHeader(encryption: Int, recordOffset: Int = 200) -> Data {
    var bytes = [UInt8](repeating: 0, count: 1024)
    // `BOOKMOBI` at offset 60 is what marks it as a MOBI.
    bytes.replaceSubrange(60..<68, with: Array("BOOKMOBI".utf8))
    // First record-info entry at 78: a big-endian offset to record 0.
    bytes[78] = UInt8((recordOffset >> 24) & 0xFF)
    bytes[79] = UInt8((recordOffset >> 16) & 0xFF)
    bytes[80] = UInt8((recordOffset >> 8) & 0xFF)
    bytes[81] = UInt8(recordOffset & 0xFF)
    // The encryption flag, 12 bytes into that record.
    bytes[recordOffset + 12] = UInt8((encryption >> 8) & 0xFF)
    bytes[recordOffset + 13] = UInt8(encryption & 0xFF)
    return Data(bytes)
}

@Suite("MOBI inspection")
struct MOBIInspectorTests {
    @Test("An unencrypted book reads as convertible")
    func noEncryption() {
        #expect(MOBIInspector.encryption(in: mobiHeader(encryption: 0)) == MOBIInspector.Encryption.none)
        #expect(MOBIInspector.Encryption.none.isProtected == false)
    }

    @Test("Both DRM schemes are recognised")
    func drmSchemes() {
        #expect(MOBIInspector.encryption(in: mobiHeader(encryption: 1)) == .legacy)
        #expect(MOBIInspector.encryption(in: mobiHeader(encryption: 2)) == .mobipocket)
        #expect(MOBIInspector.Encryption.legacy.isProtected)
        #expect(MOBIInspector.Encryption.mobipocket.isProtected)
    }

    @Test("An unknown encryption value is treated as protected, not as open")
    func unknownIsProtected() {
        // Guessing "probably fine" on an unrecognised flag would mean handing
        // a DRM-locked file to the converter and failing confusingly later.
        #expect(MOBIInspector.encryption(in: mobiHeader(encryption: 99))?.isProtected == true)
    }

    @Test("Something that is not a MOBI reads as nil")
    func notAMOBI() {
        #expect(MOBIInspector.encryption(in: Data(repeating: 0, count: 1024)) == nil)
        #expect(MOBIInspector.encryption(in: Data("not a book".utf8)) == nil)
        #expect(MOBIInspector.encryption(in: Data()) == nil)
    }

    @Test("A truncated file does not read past its end")
    func truncated() {
        // A record offset pointing beyond the data must not crash.
        let short = mobiHeader(encryption: 0, recordOffset: 900).prefix(300)
        #expect(MOBIInspector.encryption(in: Data(short)) == nil)
    }

    @Test("A DRM-protected file is refused with the spec's own wording")
    func refusesDRM() throws {
        let url = URL.temporaryDirectory.appending(path: "drm-\(UUID().uuidString).mobi")
        try mobiHeader(encryption: 2).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ConversionError.drmProtected) {
            try MOBIInspector.requireConvertible(fileAt: url)
        }
    }

    @Test("An open file passes the check")
    func allowsOpenFile() throws {
        let url = URL.temporaryDirectory.appending(path: "open-\(UUID().uuidString).mobi")
        try mobiHeader(encryption: 0).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try MOBIInspector.requireConvertible(fileAt: url)
    }

    @Test("Only the first kilobyte is ever read")
    func readsOnlyTheHeader() throws {
        // A 40 MB book should not be loaded into memory to answer this.
        var data = mobiHeader(encryption: 0)
        data.append(Data(repeating: 0xAB, count: 5_000_000))
        let url = URL.temporaryDirectory.appending(path: "big-\(UUID().uuidString).mobi")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MOBIInspector.bytesNeeded == 1024)
        #expect(try MOBIInspector.encryption(ofFileAt: url) == MOBIInspector.Encryption.none)
    }
}

@Suite("Converted EPUB validation")
struct ConvertedEPUBValidationTests {
    /// The first 58 bytes of a real EPUB: a ZIP local header whose first entry
    /// is an uncompressed `mimetype` containing `application/epub+zip`.
    private func epubPrefix() -> Data {
        var bytes = [UInt8]([0x50, 0x4B, 0x03, 0x04])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 26))
        bytes.append(contentsOf: Array("mimetype".utf8))
        bytes.append(contentsOf: Array("application/epub+zip".utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 64))
        return Data(bytes)
    }

    @Test("A well-formed EPUB passes")
    func acceptsValid() throws {
        try MOBIConverter.validate(epubPrefix())
    }

    @Test("A ZIP that is not an EPUB is rejected")
    func rejectsPlainZip() {
        var bytes = [UInt8]([0x50, 0x4B, 0x03, 0x04])
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 26))
        bytes.append(contentsOf: Array("notmime".utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 80))
        #expect(throws: ConversionError.self) { try MOBIConverter.validate(Data(bytes)) }
    }

    @Test("Something that is not a ZIP at all is rejected")
    func rejectsNonZip() {
        #expect(throws: ConversionError.self) {
            try MOBIConverter.validate(Data(repeating: 0x41, count: 500))
        }
    }

    @Test("An empty result is rejected rather than written out")
    func rejectsEmpty() {
        // Writing a zero-byte "EPUB" would fail later and somewhere else.
        #expect(throws: ConversionError.self) { try MOBIConverter.validate(Data()) }
    }

    @Test("The cache path is derived from the source name")
    func cachePath() {
        let url = MOBIConverter.cacheURL(for: URL(fileURLWithPath: "/tmp/The Hobbit.azw3"))
        #expect(url.lastPathComponent == "The Hobbit.epub")
        #expect(url.path(percentEncoded: false).contains("Firelight/Converted"))
    }
}

@Suite("Bundled converter resources")
struct ConverterResourceTests {
    @Test("Everything the web view loads is actually in the bundle")
    func resourcesPresent() throws {
        // A missing resource means the converter fails at runtime only, on a
        // device, with a book the user chose.
        for (name, ext) in [("converter", "html"), ("converter", "js"), ("mobi", "js"), ("jszip.min", "js")] {
            #expect(
                Bundle.module.url(forResource: name, withExtension: ext) != nil,
                "\(name).\(ext) is missing from the bundle"
            )
        }
    }

    @Test("The third-party licences ship with them")
    func licencesPresent() throws {
        for name in ["foliate-js-LICENSE", "jszip-LICENSE"] {
            let url = try #require(
                Bundle.module.url(forResource: name, withExtension: "txt")
            )
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("MIT"), "\(name) should be MIT")
        }
    }
}
