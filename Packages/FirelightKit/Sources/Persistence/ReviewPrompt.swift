import Foundation

/// When to ask the listener to rate Firelight.
///
/// Three opens is the whole rule: enough that they have come back of their own
/// accord, early enough that they still remember deciding to. StoreKit caps
/// the real prompt at three a year however often this says yes, so the rule
/// only has to be reasonable — it does not have to be defensive.
public enum ReviewPrompt {
    /// Opens before the first ask, and between asks after that.
    public static let opensBetweenAsks = 3

    /// What the app last did about asking.
    public struct Ask: Sendable, Hashable {
        /// The version that asked. A later version may ask again; this one
        /// never asks twice.
        public let version: String
        /// How many opens had happened by then.
        public let opens: Int

        public init(version: String, opens: Int) {
            self.version = version
            self.opens = opens
        }
    }

    /// Pure on purpose, so the rule is testable without a defaults store, a
    /// bundle or a window to put a prompt in.
    public static func shouldAsk(opens: Int, lastAsk: Ask?, version: String) -> Bool {
        guard let lastAsk else { return opens >= opensBetweenAsks }
        // Never twice for the same build, and not again until they have come
        // back as many times as it took to earn the first ask.
        return lastAsk.version != version && opens >= lastAsk.opens + opensBetweenAsks
    }
}

/// Counts opens and remembers whether we have asked.
///
/// Defaults-backed for the reason `ReadingEditionStore` gives at length: two
/// integers and a string are not worth a schema version, and this project's
/// migration plan covers two stores at once, so adding a model to one of them
/// forces a no-op bump on the other. `@unchecked` for the same reason as well
/// — `UserDefaults` is thread-safe but unmarked, and this type adds no
/// mutable state of its own.
public struct ReviewPromptStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let opensKey = "firelight.review.opens"
    private static let askVersionKey = "firelight.review.askedVersion"
    private static let askOpensKey = "firelight.review.askedAtOpens"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroup.defaults ?? .standard
    }

    /// How many times the app has been opened to a configured server.
    public var opens: Int { defaults.integer(forKey: Self.opensKey) }

    /// The last ask, if there has been one.
    public var lastAsk: ReviewPrompt.Ask? {
        guard let version = defaults.string(forKey: Self.askVersionKey) else { return nil }
        return ReviewPrompt.Ask(version: version, opens: defaults.integer(forKey: Self.askOpensKey))
    }

    /// Counts this open and says whether it is the one to ask on.
    ///
    /// The ask is recorded here rather than when the prompt appears, because
    /// StoreKit will not say whether it showed anything — and an ask we cannot
    /// see is still one we should not repeat.
    @discardableResult
    public func recordOpen(version: String = ReviewPromptStore.currentVersion) -> Bool {
        let opens = self.opens + 1
        defaults.set(opens, forKey: Self.opensKey)
        guard ReviewPrompt.shouldAsk(opens: opens, lastAsk: lastAsk, version: version) else {
            return false
        }
        defaults.set(version, forKey: Self.askVersionKey)
        defaults.set(opens, forKey: Self.askOpensKey)
        return true
    }

    /// The marketing version, which is what a reader would recognise as "the
    /// version I rated".
    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
