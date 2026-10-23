import Foundation
import Observation
import Persistence
import ReaderKit

/// Where the listener would be in the printed book.
///
/// Two pieces of state, deliberately separate. The *device* is a property of
/// the person — they own one e-reader and it does not change between books —
/// and lives in defaults. The *edition* is a property of one book and lives in
/// the synced store, because the listener had to read a number off their own
/// copy to get it and should not have to do that twice.
/// Which end of the text a calibration point refers to.
public enum CalibrationEnd: Sendable {
    case start
    case finish
}

@MainActor
@Observable
public final class FollowAlongController {
    public private(set) var isEnabled: Bool
    public private(set) var device: ReadingDevice
    /// Only meaningful when `device` is `.kindle`; it tailors the help text
    /// and nothing else.
    public private(set) var kindleModel: KindleModel
    /// The edition for whichever book is loaded, if the listener set one.
    public private(set) var edition: ReadingEdition?

    @ObservationIgnored private var loadedItemID: String?
    @ObservationIgnored private let store: ReadingEditionStore
    @ObservationIgnored private let defaults: UserDefaults

    private static let enabledKey = "firelight.followAlong.enabled"
    private static let deviceKey = "firelight.followAlong.device"
    private static let kindleModelKey = "firelight.followAlong.kindleModel"

    public init(store: ReadingEditionStore = ReadingEditionStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.device = defaults.string(forKey: Self.deviceKey)
            .flatMap(ReadingDevice.init(rawValue:)) ?? .kindle
        self.kindleModel = defaults.string(forKey: Self.kindleModelKey)
            .flatMap(KindleModel.init(rawValue:)) ?? .paperwhite
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    public func setKindleModel(_ model: KindleModel) {
        kindleModel = model
        defaults.set(model.rawValue, forKey: Self.kindleModelKey)
    }

    public func setDevice(_ newDevice: ReadingDevice) {
        device = newDevice
        defaults.set(newDevice.rawValue, forKey: Self.deviceKey)
    }

    /// Loads the edition for a book. Cheap to call repeatedly.
    public func load(itemID: String) {
        guard loadedItemID != itemID else { return }
        loadedItemID = itemID
        edition = nil
        guard let stored = store.edition(forItemID: itemID) else { return }
        edition = Self.edition(from: stored, fallbackUnit: device.defaultUnit)
    }

    public func save(itemID: String, edition newEdition: ReadingEdition) {
        let stored = store.save(
            StoredReadingEdition(
                itemID: itemID,
                deviceRaw: device.rawValue,
                unitRaw: newEdition.unit.rawValue,
                firstPosition: newEdition.firstPosition,
                lastPosition: newEdition.lastPosition,
                startProgress: newEdition.startProgress,
                endProgress: newEdition.endProgress
            )
        )
        loadedItemID = itemID
        edition = Self.edition(from: stored, fallbackUnit: newEdition.unit)
    }

    /// Calibrates one end against where the audio actually is.
    public func calibrate(itemID: String, end: CalibrationEnd, atProgress progress: Double) {
        guard var current = edition else { return }
        switch end {
        case .start: current.startProgress = min(max(progress, 0), 1)
        case .finish: current.endProgress = min(max(progress, 0), 1)
        }
        save(itemID: itemID, edition: current)
    }

    /// Puts both ends back to the whole audio.
    public func clearCalibration(itemID: String) {
        guard var current = edition else { return }
        current.startProgress = 0
        current.endProgress = 1
        save(itemID: itemID, edition: current)
    }

    private static func edition(
        from stored: StoredReadingEdition,
        fallbackUnit: ReadingUnit
    ) -> ReadingEdition {
        ReadingEdition(
            unit: ReadingUnit(rawValue: stored.unitRaw) ?? fallbackUnit,
            firstPosition: stored.firstPosition,
            lastPosition: stored.lastPosition,
            startProgress: stored.startProgress,
            endProgress: stored.endProgress
        )
    }

    public func forget(itemID: String) {
        store.remove(itemID: itemID)
        if loadedItemID == itemID { edition = nil }
    }

    /// Where the listener is in print, or nil when there is nothing honest to
    /// say — following along is off, or this book has no edition recorded.
    public func position(progress: Double) -> FollowAlongPosition? {
        guard isEnabled, let edition else { return nil }
        return FollowAlong.position(progress: progress, edition: edition)
    }
}
