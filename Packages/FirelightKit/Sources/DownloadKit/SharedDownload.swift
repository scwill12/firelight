import Foundation

/// Prepares a downloaded book for the share sheet.
///
/// Downloads are stored under the server's inode number — `9472913.m4b` —
/// which is right for a cache and useless to a person. AirDropping that gives
/// the recipient a file they cannot identify, so the files are copied into the
/// temporary directory under the book's own name first.
///
/// Copies, not moves or links: the originals stay where playback expects them,
/// and the staged ones live in `tmp`, which the system reclaims on its own.
public enum SharedDownload {
    /// What a book's files are called once they are fit to hand to someone.
    ///
    /// One file takes the book's name. Several are numbered, because a folder
    /// of identically-named tracks is worse than no names at all, and the
    /// order is the only thing a listener needs to reassemble them.
    public static func fileName(
        title: String,
        index: Int,
        of count: Int,
        extension ext: String
    ) -> String {
        let safe = sanitised(title)
        guard count > 1 else { return "\(safe).\(ext)" }
        // Zero-padded so a file listing sorts the way the book reads.
        let width = String(count).count
        let number = String(format: "%0\(width)d", index + 1)
        return "\(safe) \(number) of \(count).\(ext)"
    }

    /// Strips what a file system cannot take, and trims what would look odd.
    ///
    /// `/` and `:` are the two that genuinely break a path — the colon because
    /// the Finder still shows it as a separator — and a leading dot would hide
    /// the file.
    public static func sanitised(_ title: String) -> String {
        var cleaned = title
        for character in ["/", ":", "\\", "?", "%", "*", "|", "\"", "<", ">"] {
            cleaned = cleaned.replacingOccurrences(of: character, with: " ")
        }
        cleaned = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Audiobook" : String(trimmed.prefix(120))
    }

    /// Copies `sources` into a fresh temporary folder under readable names and
    /// returns them in order. Throws rather than returning a partial set: half
    /// an audiobook handed to someone is worse than an error.
    public static func stage(
        title: String,
        sources: [URL],
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard !sources.isEmpty else { return [] }

        let folder = fileManager.temporaryDirectory
            .appending(path: "FirelightShare/\(UUID().uuidString)")
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var staged: [URL] = []
        for (index, source) in sources.enumerated() {
            let ext = source.pathExtension.isEmpty ? "m4b" : source.pathExtension
            let destination = folder.appending(path: fileName(
                title: title, index: index, of: sources.count, extension: ext
            ))
            try fileManager.copyItem(at: source, to: destination)
            staged.append(destination)
        }
        return staged
    }

    /// Clears anything staged by an earlier share.
    ///
    /// `tmp` is reclaimed by the system eventually, but "eventually" can be
    /// days, and an audiobook is not a small thing to leave lying about twice.
    public static func clearStaged(fileManager: FileManager = .default) {
        let root = fileManager.temporaryDirectory.appending(path: "FirelightShare")
        try? fileManager.removeItem(at: root)
    }
}
