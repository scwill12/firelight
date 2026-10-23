import Foundation

/// Carrying the current item between a user's devices.
///
/// The payload is deliberately small and self-describing: an activity can
/// arrive on a device that has never seen this server, or seconds after the
/// user signed out, so everything the receiver needs to decide what to do is
/// in the dictionary and every field is checked on the way back out.
public enum HandoffActivity {
    /// Also declared in the app's `NSUserActivityTypes`, or the system ignores it.
    public static let itemType = "com.colewilliams.firelight.item"

    public enum Key {
        public static let serverID = "serverID"
        public static let itemID = "itemID"
        public static let position = "position"
        public static let title = "title"
    }

    public struct Payload: Sendable, Hashable {
        public let serverID: UUID
        public let itemID: String
        /// Seconds into the book, when the sending device was playing it.
        public let position: TimeInterval?
        public let title: String?

        public init(serverID: UUID, itemID: String, position: TimeInterval? = nil, title: String? = nil) {
            self.serverID = serverID
            self.itemID = itemID
            self.position = position
            self.title = title
        }
    }

    public static func userInfo(for payload: Payload) -> [String: Any] {
        var info: [String: Any] = [
            Key.serverID: payload.serverID.uuidString,
            Key.itemID: payload.itemID,
        ]
        if let position = payload.position { info[Key.position] = position }
        if let title = payload.title { info[Key.title] = title }
        return info
    }

    /// Reads an incoming activity. Returns nil for anything malformed rather
    /// than guessing — a half-understood handoff would open the wrong book.
    public static func payload(from userInfo: [AnyHashable: Any]?) -> Payload? {
        guard let userInfo,
              let serverString = userInfo[Key.serverID] as? String,
              let serverID = UUID(uuidString: serverString),
              let itemID = userInfo[Key.itemID] as? String,
              !itemID.isEmpty
        else { return nil }

        let position = userInfo[Key.position] as? TimeInterval
        return Payload(
            serverID: serverID,
            itemID: itemID,
            // A negative or non-finite position is not a position.
            position: (position?.isFinite == true && (position ?? 0) >= 0) ? position : nil,
            title: userInfo[Key.title] as? String
        )
    }
}
