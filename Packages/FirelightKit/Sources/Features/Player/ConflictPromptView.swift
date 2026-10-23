import DesignSystem
import PlaybackKit
import SwiftUI
import SyncEngine

/// Asks which position to keep.
///
/// This is the one screen that exists purely to stop the app losing someone's
/// place. It shows both positions with the device that produced each, and it
/// has no default and no dismiss-by-tapping-away: a wrong guess here is the
/// bug the whole sync engine is built to avoid.
struct ConflictPromptView: View {
    let conflict: ProgressSyncService.PendingConflict
    let onChoose: (Bool) -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(Palette.accent)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, Spacing.xl)

            VStack(spacing: Spacing.xs) {
                Text(L("Two places to pick up from"))
                    .font(Typography.sectionTitle)
                    .foregroundStyle(Palette.primaryText)
                Text(L("This book moved on another device. Which one is right?"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .accessibilityElement(children: .combine)

            VStack(spacing: Spacing.m) {
                choice(
                    position: conflict.remote,
                    label: L("Continue from \(PlaybackController.timecode(conflict.remote.currentTime ?? 0)) on \(conflict.remote.deviceLabel)"),
                    isPrimary: true
                ) { onChoose(true) }

                choice(
                    position: conflict.local,
                    label: L("Stay at \(PlaybackController.timecode(conflict.local.currentTime ?? 0))"),
                    isPrimary: false
                ) { onChoose(false) }
            }
            .padding(.horizontal, Spacing.l)

            Text(L("Firelight keeps both in this book's history, so nothing is lost either way."))
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Spacer(minLength: Spacing.l)
        }
        .background(Palette.background)
        .interactiveDismissDisabled()
        .presentationDetents([.medium])
    }

    private func choice(
        position: ProgressPosition,
        label: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: label)
                    .font(Typography.emphasisedBody)
                    .multilineTextAlignment(.leading)
                Text(verbatim: position.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.caption)
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
        }
        .buttonStyle(.borderedProminent)
        .tint(isPrimary ? Palette.accent : Palette.separator)
        .foregroundStyle(isPrimary ? Color.white : Palette.primaryText)
    }
}

/// Every position this book has been at, and where it came from.
struct PositionHistoryView: View {
    let itemID: String

    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [ProgressJournalEntry] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if entries.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: Text(L("No history yet")),
                    message: Text(L("Positions appear here as you listen, on every device."))
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        Button {
                            environment.player.applyRemotePosition(entry.position)
                        } label: {
                            LabeledContent {
                                Text(verbatim: PlaybackController.timecode(entry.position.currentTime ?? 0))
                                    .font(Typography.timecode)
                                    .foregroundStyle(Palette.accent)
                            } label: {
                                VStack(alignment: .leading, spacing: Spacing.hair) {
                                    Text(verbatim: entry.position.deviceLabel)
                                        .foregroundStyle(Palette.primaryText)
                                    HStack(spacing: Spacing.xs) {
                                        Text(verbatim: entry.position.updatedAt.formatted(
                                            date: .abbreviated, time: .shortened
                                        ))
                                        if entry.syncState == .pending {
                                            Text(L("Not synced yet"))
                                                .foregroundStyle(Palette.notice)
                                        }
                                    }
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.secondaryText)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(L("Jumps to this position"))
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(Text(L("Position history")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            entries = await environment.sync.history(itemID: itemID)
            isLoading = false
        }
    }
}
