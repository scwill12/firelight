import ABSKit
import Foundation
import Persistence

/// One foundation self-check and its result.
///
/// Phase 0 ships the plumbing every later phase depends on: a shared App Group
/// container, a shared Keychain, and a SwiftData store inside the container.
/// All three fail in ways that only show up on a real device with real
/// entitlements, so the app checks them itself and says so plainly rather than
/// failing mysteriously in Phase 1.
public struct FoundationCheck: Sendable, Hashable, Identifiable {
    public enum Outcome: Sendable, Hashable {
        case passed(detail: String)
        case failed(detail: String)

        public var didPass: Bool {
            if case .passed = self { return true }
            return false
        }

        public var detail: String {
            switch self {
            case .passed(let detail), .failed(let detail): detail
            }
        }
    }

    public let id: String
    public let name: String
    public let outcome: Outcome

    public init(id: String, name: String, outcome: Outcome) {
        self.id = id
        self.name = name
        self.outcome = outcome
    }
}

/// Runs the checks. Takes its dependencies rather than reaching for them, so a
/// test can run it against an in-memory store and a Keychain store with no
/// access group.
public struct FoundationChecker: Sendable {
    private let keychain: KeychainStore
    private let storeOpened: Bool
    private let storeFailureDetail: String?

    public init(keychain: KeychainStore, storeOpened: Bool, storeFailureDetail: String? = nil) {
        self.keychain = keychain
        self.storeOpened = storeOpened
        self.storeFailureDetail = storeFailureDetail
    }

    public func run() -> [FoundationCheck] {
        [appGroupCheck(), keychainCheck(), storeCheck()]
    }

    func appGroupCheck() -> FoundationCheck {
        guard AppGroup.containerURL != nil else {
            return FoundationCheck(
                id: "appGroup",
                name: "Shared container",
                outcome: .failed(detail: "The App Group isn't in this build's entitlements.")
            )
        }
        return FoundationCheck(
            id: "appGroup",
            name: "Shared container",
            outcome: .passed(detail: AppGroup.identifier)
        )
    }

    /// Writes a value, reads it back, deletes it. The only way to know the
    /// Keychain access group actually works on this device.
    func keychainCheck() -> FoundationCheck {
        let key = "firelight.foundationCheck"
        let expected = UUID().uuidString
        do {
            try keychain.setString(expected, for: key)
            let readBack = try keychain.string(for: key)
            try keychain.remove(key)
            guard readBack == expected else {
                return FoundationCheck(
                    id: "keychain",
                    name: "Shared Keychain",
                    outcome: .failed(detail: "Wrote a value but read back something else.")
                )
            }
            let group = keychain.accessGroup == nil ? "no access group" : "shared access group"
            return FoundationCheck(id: "keychain", name: "Shared Keychain", outcome: .passed(detail: group))
        } catch KeychainError.unexpectedStatus(let status) {
            return FoundationCheck(
                id: "keychain",
                name: "Shared Keychain",
                outcome: .failed(detail: "Keychain returned status \(status).")
            )
        } catch {
            return FoundationCheck(
                id: "keychain",
                name: "Shared Keychain",
                outcome: .failed(detail: "Couldn't write to the Keychain.")
            )
        }
    }

    func storeCheck() -> FoundationCheck {
        if storeOpened {
            return FoundationCheck(id: "store", name: "Local database", outcome: .passed(detail: "Schema v1"))
        }
        return FoundationCheck(
            id: "store",
            name: "Local database",
            outcome: .failed(detail: storeFailureDetail ?? "The store didn't open.")
        )
    }
}
