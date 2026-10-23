import Foundation
import Persistence
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

/// Who wrote a position. Every journal entry carries one, which is what makes
/// the position-history screen ("3:42:10 on iPad") possible.
public struct DeviceIdentity: Sendable, Hashable, Codable {
    /// Stable for the life of the install, shared across this device's targets.
    public let id: String
    /// A human label. Deliberately the *model* name, not the user's device
    /// name: `UIDevice.name` needs an entitlement and returns a generic string
    /// without one, and the model is what a user actually recognises in a list.
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    private static let idKey = "firelight.deviceIdentity.id"
    private static let labelKey = "firelight.deviceIdentity.label"

    /// Reads the shared identity, creating it on first launch and caching the
    /// label so `cached()` can be used off the main actor.
    @MainActor
    public static func current() -> DeviceIdentity {
        let defaults = AppGroup.defaults ?? .standard
        let label = currentLabel()
        defaults.set(label, forKey: labelKey)
        return DeviceIdentity(id: persistentID(in: defaults), label: label)
    }

    /// The identity without touching UIKit, for the background contexts that
    /// stamp journal entries. Falls back to a neutral label if the app has not
    /// run since install.
    public static func cached() -> DeviceIdentity {
        let defaults = AppGroup.defaults ?? .standard
        return DeviceIdentity(
            id: persistentID(in: defaults),
            label: defaults.string(forKey: labelKey) ?? "This device"
        )
    }

    private static func persistentID(in defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: idKey) { return existing }
        let id = UUID().uuidString
        defaults.set(id, forKey: idKey)
        return id
    }

    @MainActor
    static func currentLabel() -> String {
        #if os(watchOS)
        return WKInterfaceDevice.current().model
        #elseif canImport(UIKit)
        return UIDevice.current.localizedModel
        #else
        return "Mac"
        #endif
    }
}
