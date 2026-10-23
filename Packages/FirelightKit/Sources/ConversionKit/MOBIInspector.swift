import Foundation

/// Reads just enough of a MOBI/AZW3 to know whether it can be converted.
///
/// DRM is the common reason a conversion fails, and finding out *after*
/// spinning up a web view and parsing a 40 MB book is a poor way to learn it.
/// The encryption flag lives 12 bytes into the PalmDOC header, which is a
/// handful of bytes at a known offset.
public enum MOBIInspector {
    public enum Encryption: Int, Sendable, Hashable {
        case none = 0
        /// Old Mobipocket scheme.
        case legacy = 1
        /// Mobipocket DRM.
        case mobipocket = 2

        public var isProtected: Bool { self != .none }
    }

    /// The PalmDB header is 78 bytes, then 8 bytes per record-info entry.
    static let palmHeaderLength = 78
    static let recordInfoLength = 8

    /// How much of the file `encryption(in:)` needs. The rest never has to be
    /// read.
    public static let bytesNeeded = 1024

    /// Reads the encryption flag, or nil when the bytes are not a PalmDB.
    public static func encryption(in header: Data) -> Encryption? {
        let bytes = [UInt8](header)
        guard bytes.count >= palmHeaderLength + recordInfoLength else { return nil }

        // `BOOKMOBI` at offset 60 is what makes this a MOBI rather than some
        // other PalmDB.
        let type = String(decoding: bytes[60..<68], as: UTF8.self)
        guard type == "BOOKMOBI" else { return nil }

        // First record-info entry: a 4-byte big-endian offset to record 0.
        let recordOffset = Int(
            UInt32(bytes[78]) << 24 | UInt32(bytes[79]) << 16
            | UInt32(bytes[80]) << 8 | UInt32(bytes[81])
        )
        // The encryption field is 12 bytes into that record.
        guard recordOffset >= 0, bytes.count >= recordOffset + 14 else { return nil }

        let raw = Int(UInt16(bytes[recordOffset + 12]) << 8 | UInt16(bytes[recordOffset + 13]))
        return Encryption(rawValue: raw) ?? .mobipocket
    }

    /// Reads only the first kilobyte from disk.
    public static func encryption(ofFileAt url: URL) throws -> Encryption? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: bytesNeeded) ?? Data()
        return encryption(in: header)
    }

    /// Throws the error the reader shows, so the check reads as one line.
    public static func requireConvertible(fileAt url: URL) throws {
        guard let encryption = try encryption(ofFileAt: url) else {
            throw ConversionError.parseFailed(stage: "header")
        }
        if encryption.isProtected {
            throw ConversionError.drmProtected
        }
    }
}
