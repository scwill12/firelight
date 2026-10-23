import Foundation
import SwiftData

/// Schema v1: servers and accounts only, as Phase 0 shipped it.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [ServerRecord.self, UserRecord.self]
    }
}

/// Schema v2 adds the library cache. Purely additive, so the migration is
/// lightweight and nobody loses their servers on upgrade.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self]
    }
}

/// Schema v3 adds the progress journal. Additive again — and this one holds
/// positions that exist nowhere else when the user is offline, so a botched
/// migration here is lost listening, not a slow first launch.
public enum SchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self, JournalEntryRecord.self]
    }
}

/// Always migrate forward through stages; never mutate a released schema in
/// place. Offline progress lives in this store from Phase 4 on, so a failed
/// migration is data loss, not an inconvenience.
public enum FirelightMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]
    }

    public static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
            .lightweight(fromVersion: SchemaV4.self, toVersion: SchemaV5.self),
            .lightweight(fromVersion: SchemaV5.self, toVersion: SchemaV6.self),
            .lightweight(fromVersion: SchemaV6.self, toVersion: SchemaV7.self),
        ]
    }
}

/// Schema v4 adds downloads. Additive again.
public enum SchemaV4: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self,
            JournalEntryRecord.self, DownloadRecord.self, DownloadedFile.self,
        ]
    }
}

/// Schema v5 adds highlights. These are the user's own writing and exist
/// nowhere else, so this table is as precious as the journal.
public enum SchemaV5: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self,
            JournalEntryRecord.self, DownloadRecord.self, DownloadedFile.self,
            HighlightRecord.self,
        ]
    }
}

/// Schema v6 adds podcast episodes.
public enum SchemaV6: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self,
            JournalEntryRecord.self, DownloadRecord.self, DownloadedFile.self,
            HighlightRecord.self, CachedEpisode.self,
        ]
    }
}

/// Schema v7 moves highlights into their own CloudKit-backed configuration.
///
/// They are the only thing in the app the user *wrote*; everything else is a
/// cache of the server or can be rebuilt from it, and syncing a library cache
/// through iCloud would be both pointless and slow.
public enum SchemaV7: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(7, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self,
            JournalEntryRecord.self, DownloadRecord.self, DownloadedFile.self,
            HighlightRecord.self, CachedEpisode.self,
        ]
    }

    /// The models that stay on this device.
    public static var localModels: [any PersistentModel.Type] {
        [
            ServerRecord.self, UserRecord.self, CachedLibrary.self, CachedItem.self,
            JournalEntryRecord.self, DownloadRecord.self, DownloadedFile.self,
            CachedEpisode.self,
        ]
    }

    /// The models that follow the user between their devices.
    public static var syncedModels: [any PersistentModel.Type] {
        [HighlightRecord.self]
    }
}

/// The schema the app currently opens.
public typealias CurrentSchema = SchemaV7

/// The private iCloud container. Must exist in the developer portal, and be
/// listed in the app's entitlements, or the container falls back to local-only.
public enum CloudKitContainer {
    public static let identifier = "iCloud.com.colewilliams.firelight"
}

/// A server the user has added. Addresses and display name only — tokens,
/// custom headers and trusted certificates live in the Keychain, keyed by `id`.
@Model
public final class ServerRecord {
    #Index<ServerRecord>([\.id])
    @Attribute(.unique) public var id: UUID
    public var displayName: String
    public var localURLString: String?
    public var remoteURLString: String
    /// Last version reported by `GET /status`, used to build the feature table
    /// before the first network call of a session.
    public var serverVersionString: String?
    public var lastConnectedAt: Date?
    /// Which address answered last, so the next launch tries that one first.
    public var lastActiveAddressRaw: String?
    public var addedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        localURLString: String? = nil,
        remoteURLString: String,
        serverVersionString: String? = nil,
        lastConnectedAt: Date? = nil,
        lastActiveAddressRaw: String? = nil,
        addedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.localURLString = localURLString
        self.remoteURLString = remoteURLString
        self.serverVersionString = serverVersionString
        self.lastConnectedAt = lastConnectedAt
        self.lastActiveAddressRaw = lastActiveAddressRaw
        self.addedAt = addedAt
    }
}

/// One signed-in ABS account on one server. A household can have several.
@Model
public final class UserRecord {
    /// `serverID` + ABS user id. ABS user ids are only unique within a server.
    @Attribute(.unique) public var compositeID: String
    public var serverID: UUID
    public var absUserID: String
    public var username: String
    public var accountType: String?
    public var defaultLibraryID: String?
    public var lastSignedInAt: Date
    /// The account the app is currently acting as.
    public var isActive: Bool

    public init(
        serverID: UUID,
        absUserID: String,
        username: String,
        accountType: String? = nil,
        defaultLibraryID: String? = nil,
        lastSignedInAt: Date = .now,
        isActive: Bool = false
    ) {
        self.compositeID = "\(serverID.uuidString):\(absUserID)"
        self.serverID = serverID
        self.absUserID = absUserID
        self.username = username
        self.accountType = accountType
        self.defaultLibraryID = defaultLibraryID
        self.lastSignedInAt = lastSignedInAt
        self.isActive = isActive
    }
}
