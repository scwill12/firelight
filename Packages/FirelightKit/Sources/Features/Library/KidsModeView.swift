import DesignSystem
import LocalAuthentication
import Persistence
import SwiftUI

/// A simplified library for a child.
///
/// Big covers, nothing else: no settings, no server, no admin, no search by
/// typing. Leaving requires Face ID, Touch ID or the device passcode, because
/// a mode a four-year-old can tap their way out of is not a mode.
struct KidsModeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var items: [LibraryItemSummary] = []
    @State private var isUnlocking = false
    @State private var unlockFailed = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: Spacing.l)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(items) { item in
                        Button {
                            Task { await environment.play(item: item) }
                        } label: {
                            VStack(spacing: Spacing.s) {
                                CoverImage(itemID: item.id, title: item.title)
                                    .aspectRatio(CoverArt.aspectRatio, contentMode: .fit)
                                    .shadow(
                                        color: .black.opacity(Elevation.cardShadowOpacity),
                                        radius: Elevation.cardShadowRadius,
                                        y: Elevation.cardShadowY
                                    )
                                Text(verbatim: item.title)
                                    .font(Typography.itemTitle)
                                    .foregroundStyle(Palette.primaryText)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(Spacing.l)
            }
            .navigationTitle(Text(L("Listen")))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await unlock() }
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .accessibilityLabel(L("Leave kids mode"))
                    .disabled(isUnlocking)
                }
            }
            .alert(L("Couldn't unlock"), isPresented: $unlockFailed) {
                Button(L("OK"), role: .cancel) {}
            } message: {
                Text(L("Kids mode stays on until Face ID, Touch ID or your passcode says otherwise."))
            }
            .overlay {
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "books.vertical",
                        title: Text(L("Nothing here yet")),
                        message: Text(L("Ask a grown-up to add some books."))
                    )
                }
            }
        }
        .task { items = await environment.library.items(sort: .title) }
    }

    /// The whole point of the feature, so it fails closed: any error, any
    /// cancellation, and kids mode stays on.
    private func unlock() async {
        isUnlocking = true
        defer { isUnlocking = false }

        let context = LAContext()
        context.localizedCancelTitle = L("Stay in kids mode")

        var error: NSError?
        // `.deviceOwnerAuthentication` includes the passcode, so a device with
        // no biometrics can still leave.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            unlockFailed = true
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: L("Leave kids mode")
            )
            if success {
                environment.setKidsMode(false)
            } else {
                unlockFailed = true
            }
        } catch {
            unlockFailed = true
        }
    }
}
