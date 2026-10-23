import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

/// The haptics vocabulary, so a chapter change feels the same everywhere.
///
/// Main-actor isolated because the feedback generators are. Calls are
/// deliberately cheap and fire-and-forget: a haptic must never be awaited on a
/// path that also moves audio.
@MainActor
public enum Haptics {
    public enum Impact: Sendable {
        case light
        case medium
        case heavy
        /// Crossing a chapter mark while scrubbing.
        case chapterMark
    }

    public static func impact(_ impact: Impact) {
        #if os(iOS)
        let style: UIImpactFeedbackGenerator.FeedbackStyle = switch impact {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        case .chapterMark: .rigid
        }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    /// Moving between discrete values — a speed step, a sleep-timer option.
    public static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
    }

    public static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    public static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.failure)
        #endif
    }

    /// The sleep timer reaching zero.
    public static func timerEnded() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
    }
}
