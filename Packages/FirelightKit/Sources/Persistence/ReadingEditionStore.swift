import Foundation

/// Which edition of each book the listener follows along in.
///
/// Kept in the App Group's defaults rather than SwiftData, and the reason is
/// worth writing down. The data is one integer and one unit per book — far
/// less than the machinery costs. More to the point, the schema is split into
/// a local store and a CloudKit-backed one under a single migration plan, and
/// SwiftData rejects any plan whose stage leaves one of those stores
/// unchanged ("Duplicate version checksums across stages"). Adding a model to
/// either side would therefore force a no-op version bump on the other. A
/// dictionary avoids the whole argument.
///
/// The cost is that editions do not follow the listener to another device.
/// Highlights still do; these do not. If that becomes worth fixing, the fix
/// is a second `ModelContainer` with its own schema, not a stage here.
/// `@unchecked` for the same reason as `PlaybackSettingsStore`: `UserDefaults`
/// is documented as thread-safe but is not marked `Sendable`, and this type
/// adds no mutable state of its own.
public struct ReadingEditionStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "firelight.followAlong.editions"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroup.defaults ?? .standard
    }

    /// The edition recorded for one book, if there is one.
    public func edition(forItemID itemID: String) -> StoredReadingEdition? {
        all()[itemID].map {
            StoredReadingEdition(
                itemID: itemID,
                deviceRaw: $0.deviceRaw,
                unitRaw: $0.unitRaw,
                firstPosition: $0.firstPosition ?? 1,
                lastPosition: $0.lastPosition ?? $0.total ?? 0,
                startProgress: $0.startProgress ?? 0,
                endProgress: $0.endProgress ?? 1
            )
        }
    }

    /// Records an edition, replacing whatever was there for that book.
    @discardableResult
    public func save(_ edition: StoredReadingEdition) -> StoredReadingEdition {
        var editions = all()
        editions[edition.itemID] = Entry(
            deviceRaw: edition.deviceRaw,
            unitRaw: edition.unitRaw,
            total: nil,
            firstPosition: edition.firstPosition,
            lastPosition: edition.lastPosition,
            startProgress: edition.startProgress,
            endProgress: edition.endProgress
        )
        write(editions)
        return edition
    }

    /// Forgets the edition for one book.
    public func remove(itemID: String) {
        var editions = all()
        editions.removeValue(forKey: itemID)
        write(editions)
    }

    // MARK: - Private

    /// Every field after `unitRaw` is optional so that an entry written
    /// before calibration existed still decodes: `total` was what
    /// `lastPosition` is now.
    private struct Entry: Codable, Sendable {
        var deviceRaw: String
        var unitRaw: String
        var total: Int?
        var firstPosition: Int?
        var lastPosition: Int?
        var startProgress: Double?
        var endProgress: Double?
    }

    private func all() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private func write(_ editions: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(editions) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// An edition read out of the store.
public struct StoredReadingEdition: Sendable, Hashable {
    public let itemID: String
    public let deviceRaw: String
    public let unitRaw: String
    public let firstPosition: Int
    public let lastPosition: Int
    public let startProgress: Double
    public let endProgress: Double

    public init(
        itemID: String,
        deviceRaw: String,
        unitRaw: String,
        firstPosition: Int = 1,
        lastPosition: Int,
        startProgress: Double = 0,
        endProgress: Double = 1
    ) {
        self.itemID = itemID
        self.deviceRaw = deviceRaw
        self.unitRaw = unitRaw
        self.firstPosition = firstPosition
        self.lastPosition = lastPosition
        self.startProgress = startProgress
        self.endProgress = endProgress
    }
}
