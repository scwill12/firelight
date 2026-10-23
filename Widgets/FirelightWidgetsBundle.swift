import SwiftUI
import WidgetKit

@main
struct FirelightWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ContinueListeningWidget()
        StreakWidget()
        PlaybackLiveActivity()
    }
}
