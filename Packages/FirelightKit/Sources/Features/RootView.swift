import DesignSystem
import SwiftUI

/// The app's root.
///
/// With no server configured the whole app is onboarding; there is nothing
/// else it could usefully show. Once there is one, the library takes over.
public struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var handoffItemID: String?

    public init() {}

    public var body: some View {
        Group {
            if environment.session.servers.isEmpty {
                OnboardingView(isFirstServer: true)
            } else if environment.isKidsMode {
                KidsModeView()
            } else {
                AdaptiveRootView()
            }
        }
        .environment(\.coverImageProvider, environment.coverProvider)
        .tint(Palette.accent)
        .onContinueUserActivity(HandoffActivity.itemType) { activity in
            guard let payload = HandoffActivity.payload(from: activity.userInfo) else { return }
            // Only act on a handoff for the server we are actually signed into;
            // the same book id on another server is a different book.
            guard payload.serverID == environment.session.activeServer?.id else { return }
            handoffItemID = payload.itemID
        }
        .sheet(item: Binding(
            get: { handoffItemID.map { HandoffTarget(itemID: $0) } },
            set: { if $0 == nil { handoffItemID = nil } }
        )) { target in
            NavigationStack {
                ItemDetailView(itemID: target.itemID)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("Done")) { handoffItemID = nil }
                        }
                    }
            }
        }
        // A conflict outranks whatever else is on screen: nothing should move
        // the user's place while this is unanswered.
        .sheet(item: Binding(
            get: { environment.sync.pendingConflict },
            set: { _ in }
        )) { conflict in
            ConflictPromptView(conflict: conflict) { takeRemote in
                Task { await environment.sync.resolveConflict(takingRemote: takeRemote) }
            }
        }
    }
}

/// Identifies the handed-off item for a sheet.
private struct HandoffTarget: Identifiable {
    let itemID: String
    var id: String { itemID }
}

#Preview("Root — no server") {
    RootView()
        .environment(AppEnvironment.preview())
}
