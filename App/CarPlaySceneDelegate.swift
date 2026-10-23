import CarPlay
import DownloadKit
import Features
import Foundation
import Persistence
import PlaybackKit

/// The CarPlay app.
///
/// CarPlay is template-driven: you hand the system a list and it draws it. The
/// hard constraint is that a driver gets a glance, so every list here is short,
/// flat and reachable in at most two taps.
///
/// **Dormant in v1.** The `com.apple.developer.carplay-audio` entitlement was
/// removed from `Firelight.entitlements` so v1 can ship before Apple grants
/// it — a build signed with an entitlement its App ID lacks fails
/// provisioning. This file and the scene declaration stay, so re-enabling is
/// one line. See PROGRESS.md.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(makeTabBar(), animated: false, completion: nil)
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func makeTabBar() -> CPTabBarTemplate {
        CPTabBarTemplate(templates: [
            continueTemplate(),
            libraryTemplate(),
            downloadsTemplate(),
            podcastsTemplate(),
        ])
    }

    // MARK: - Tabs

    private func continueTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Continue", sections: [])
        template.tabTitle = "Continue"
        template.tabImage = UIImage(systemName: "play.circle")
        template.emptyViewSubtitleVariants = ["Start something on your phone and it appears here."]

        if let snapshot = SharedState.nowPlaying {
            let item = CPListItem(
                text: snapshot.title,
                detailText: snapshot.chapterTitle ?? snapshot.author,
                image: nil
            )
            item.isPlaying = snapshot.isPlaying
            item.playbackProgress = snapshot.fraction
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    PlaybackIntentBridge.handler?.play()
                    self?.showNowPlaying()
                    completion()
                }
            }
            template.updateSections([CPListSection(items: [item])])
        }
        return template
    }

    private func libraryTemplate() -> CPListTemplate {
        // Populated from the cache by `CarPlayLibrarySource` once the app has
        // loaded; CarPlay can connect before the app has finished starting.
        let template = CPListTemplate(title: "Library", sections: [])
        template.tabTitle = "Library"
        template.tabImage = UIImage(systemName: "books.vertical")
        template.emptyViewSubtitleVariants = ["Your library appears here once Firelight has fetched it."]
        return template
    }

    private func downloadsTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Downloads", sections: [])
        template.tabTitle = "Downloads"
        template.tabImage = UIImage(systemName: "arrow.down.circle")
        template.emptyViewSubtitleVariants = ["Books you download are listed here, and play without a signal."]
        return template
    }

    private func podcastsTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Podcasts", sections: [])
        template.tabTitle = "Podcasts"
        template.tabImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
        template.emptyViewSubtitleVariants = ["Podcast libraries appear here."]
        return template
    }

    private func showNowPlaying() {
        guard let interfaceController else { return }
        interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
