import DesignSystem
import DownloadKit
import Features
import PlaybackKit
import Persistence
import SwiftUI

@main
@MainActor
struct FirelightApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    // App Intents are built by the system with nothing to
                    // inject into, so the player registers itself here.
                    PlaybackIntentBridge.register(environment.player)
                    // Loads the servers, finds a reachable address, and keeps
                    // the value the widgets and share extension read in step.
                    await environment.start()
                }
        }
        // A reading app wants a tall window, not a wide one.
        .defaultSize(width: 1100, height: 820)
        .commands { FirelightCommands(environment: environment) }
        // Lets the system wake the app when a background download finishes,
        // which is what makes a 2 GB book survive being suspended.
        .backgroundTask(.urlSession(BackgroundDownloadManager.sessionIdentifier)) {
            await environment.downloads.reload()
        }
    }
}
