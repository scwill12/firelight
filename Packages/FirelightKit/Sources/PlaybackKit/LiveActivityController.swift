import Foundation
import Persistence
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Runs the Live Activity for the current listen.
///
/// Deliberately forgiving: Live Activities can be refused (the user turned
/// them off, too many are running, the system is busy), and none of that is
/// worth an error in a player. Every failure here ends with no Live Activity
/// and playback continuing.
@MainActor
public final class LiveActivityController {
    public init() {}

    #if canImport(ActivityKit) && os(iOS)
    /// `Activity` is a plain class that ActivityKit does not annotate
    /// `Sendable`, so Swift 6 will not let its `async` methods be awaited from
    /// an actor — every `update` and `end` is rejected as a data race.
    ///
    /// It is a handle to state the system owns, not shared mutable state of
    /// ours, and it is documented as usable from any context. This box says
    /// that once, here, instead of `@unchecked` appearing at four call sites.
    private struct ActivityBox: @unchecked Sendable {
        let activity: Activity<PlaybackActivityAttributes>
    }

    private var activity: Activity<PlaybackActivityAttributes>?

    public var isRunning: Bool { activity != nil }

    /// Whether the system will accept one at all.
    public var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public func start(
        itemID: String,
        title: String,
        author: String?,
        state: PlaybackActivityAttributes.ContentState
    ) {
        guard isAvailable else { return }

        // A different book means the old activity is finished, not updated.
        if let activity, activity.attributes.itemID != itemID {
            end()
        }
        guard activity == nil else {
            update(state: state)
            return
        }

        do {
            activity = try Activity.request(
                attributes: PlaybackActivityAttributes(itemID: itemID, title: title, author: author),
                content: ActivityContent(state: state, staleDate: Self.staleDate(for: state)),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    public func update(state: PlaybackActivityAttributes.ContentState) {
        guard let activity else { return }
        let box = ActivityBox(activity: activity)
        let content = ActivityContent(state: state, staleDate: Self.staleDate(for: state))
        Task { await box.activity.update(content) }
    }

    public func end() {
        guard let activity else { return }
        self.activity = nil
        let box = ActivityBox(activity: activity)
        Task { await box.activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Marks the activity stale once it could no longer be accurate, so the
    /// system dims it rather than showing a position that has stopped moving.
    private static func staleDate(for state: PlaybackActivityAttributes.ContentState) -> Date? {
        guard state.isPlaying else { return nil }
        return min(state.projectedFinish, state.updatedAt.addingTimeInterval(8 * 3600))
    }
    #else
    public var isRunning: Bool { false }
    public var isAvailable: Bool { false }
    public func end() {}
    #endif
}
