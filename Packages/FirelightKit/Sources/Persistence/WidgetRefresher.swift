import Foundation
#if canImport(WidgetKit) && !os(watchOS)
import WidgetKit
#endif

/// Asks the system to redraw the widgets.
///
/// Wrapped so callers need not import WidgetKit or care that it is absent on
/// watchOS. Reloading is a request, not a command: the system decides when,
/// and calling it too often simply gets throttled.
public enum WidgetRefresher {
    public static func reload() {
        #if canImport(WidgetKit) && !os(watchOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public static func reload(kind: String) {
        #if canImport(WidgetKit) && !os(watchOS)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}
