import Foundation

/// What to do about two positions for the same item.
public enum ProgressConflictOutcome: Sendable, Equatable {
    /// The local position stands; nothing to show the user.
    case keepLocal
    /// Adopt the remote position silently — it is newer and close enough that
    /// moving there is not a surprise.
    case takeRemote
    /// The two positions are far enough apart that moving the user without
    /// asking would be a lost place. The UI must offer both.
    case ask(local: ProgressPosition, remote: ProgressPosition)
    /// The positions agree.
    case noChange
}

/// The rule that protects the most important invariant in the app: never move
/// someone's place without asking.
///
/// Newest timestamp wins, with one exception — if applying the newer position
/// would move the user by more than the threshold, we ask instead. That is
/// deliberately symmetric: a 22-minute jump *forward* because another device
/// got ahead is exactly as disorienting as a jump back, and the spec's own
/// example prompt ("Continue from 3:42:10 on iPad, or stay at 3:20:05?") is a
/// forward jump. Small differences in either direction are ordinary sync lag
/// and are applied silently.
public struct ProgressConflictResolver: Sendable {
    /// Seconds of audio difference that turns a silent move into a question.
    public var audioJumpThreshold: TimeInterval
    /// Fraction of an ebook (0.02 = 2%) that turns a silent move into a question.
    public var ebookJumpThreshold: Double
    /// Differences below this are treated as the same position, so float noise
    /// and one-second rounding never produce a prompt.
    public var equalityEpsilon: TimeInterval

    public init(
        audioJumpThreshold: TimeInterval = 120,
        ebookJumpThreshold: Double = 0.02,
        equalityEpsilon: TimeInterval = 1
    ) {
        self.audioJumpThreshold = audioJumpThreshold
        self.ebookJumpThreshold = ebookJumpThreshold
        self.equalityEpsilon = equalityEpsilon
    }

    public func resolve(local: ProgressPosition?, remote: ProgressPosition?) -> ProgressConflictOutcome {
        switch (local, remote) {
        case (nil, nil):
            return .noChange
        case (nil, .some):
            // Nothing local to lose.
            return .takeRemote
        case (.some, nil):
            return .keepLocal
        case (.some(let local), .some(let remote)):
            return resolve(local: local, remote: remote)
        }
    }

    public func resolve(local: ProgressPosition, remote: ProgressPosition) -> ProgressConflictOutcome {
        if remote.isEmpty && !local.isEmpty { return .keepLocal }
        if local.isEmpty && !remote.isEmpty { return .takeRemote }
        if samePlace(local, remote) {
            // Same place: a finished flag on either side still needs adopting,
            // but it never needs a prompt.
            if remote.isFinished != local.isFinished {
                return remote.updatedAt > local.updatedAt ? .takeRemote : .keepLocal
            }
            return .noChange
        }

        // Newest wins — but only silently when the move is small.
        guard remote.updatedAt > local.updatedAt else { return .keepLocal }
        return isLargeJump(from: local, to: remote) ? .ask(local: local, remote: remote) : .takeRemote
    }

    // MARK: - Distance

    func samePlace(_ a: ProgressPosition, _ b: ProgressPosition) -> Bool {
        if let timeA = a.currentTime, let timeB = b.currentTime {
            return abs(timeA - timeB) <= equalityEpsilon
        }
        if let progressA = a.ebookProgress, let progressB = b.ebookProgress {
            return abs(progressA - progressB) <= 0.0001
        }
        if a.currentTime == nil, b.currentTime == nil, a.ebookProgress == nil, b.ebookProgress == nil {
            return a.ebookLocation == b.ebookLocation
        }
        return false
    }

    func isLargeJump(from local: ProgressPosition, to remote: ProgressPosition) -> Bool {
        if let localTime = local.currentTime, let remoteTime = remote.currentTime {
            return abs(remoteTime - localTime) > audioJumpThreshold
        }
        if let localProgress = local.ebookProgress, let remoteProgress = remote.ebookProgress {
            return abs(remoteProgress - localProgress) > ebookJumpThreshold
        }
        // Different ebook locations with no percentage to compare: we cannot
        // measure the distance, so we ask rather than guess.
        if local.ebookLocation != remote.ebookLocation,
           local.ebookLocation != nil, remote.ebookLocation != nil {
            return true
        }
        return false
    }
}
