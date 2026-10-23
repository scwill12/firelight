import Foundation
import SwiftData

/// Owns the SwiftData container. Injected, never a singleton, so tests get an
/// in-memory store and previews get a seeded one.
public struct PersistenceController: Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// The real store, in the shared App Group container.
    ///
    /// Two configurations: the cache and the journal stay on this device, and
    /// the user's highlights follow them through their private iCloud
    /// database. Syncing a library cache would be slow and pointless; losing
    /// someone's annotations when they change phone would not be acceptable.
    public static func shared(syncsWithCloudKit: Bool = true) throws -> PersistenceController {
        let storeURL = try AppGroup.storeURL()

        let local = ModelConfiguration(
            "local",
            schema: Schema(CurrentSchema.localModels),
            url: storeURL,
            cloudKitDatabase: .none
        )
        let synced = ModelConfiguration(
            "synced",
            schema: Schema(CurrentSchema.syncedModels),
            url: storeURL.deletingLastPathComponent().appending(path: "FirelightSynced.store"),
            cloudKitDatabase: syncsWithCloudKit
                ? .private(CloudKitContainer.identifier)
                : .none
        )

        do {
            return PersistenceController(
                container: try ModelContainer(
                    for: Schema(versionedSchema: CurrentSchema.self),
                    migrationPlan: FirelightMigrationPlan.self,
                    configurations: local, synced
                )
            )
        } catch {
            // A missing iCloud entitlement, or a signed-out account, should
            // cost the user their sync — not their app.
            if syncsWithCloudKit {
                return try shared(syncsWithCloudKit: false)
            }
            throw PersistenceError.storeUnavailable(String(describing: type(of: error)))
        }
    }

    /// For tests and previews. Nothing touches disk, and nothing syncs.
    ///
    /// `cloudKitDatabase` defaults to `.automatic`, which switches CloudKit on
    /// as soon as the app has the iCloud entitlement — so an in-memory store
    /// would try to mirror the *library cache* to iCloud and fail to open at
    /// all. It must be `.none` explicitly.
    public static func inMemory() throws -> PersistenceController {
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: CurrentSchema.self),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return PersistenceController(
            container: try ModelContainer(
                for: Schema(versionedSchema: CurrentSchema.self),
                configurations: configuration
            )
        )
    }
}
