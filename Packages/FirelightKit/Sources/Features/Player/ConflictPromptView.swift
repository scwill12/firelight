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

/// When this book was listened to, and what each stretch covered.
///
/// Sessions rather than position marks. A list of positions answers "where
/// was I?", which matters exactly once — when two devices disagree. A list of
/// sessions answers "when did I listen, and for how long?", which is what
/// someone wants from a book they have been at for a fortnight. The raw marks
/// are still here, one tap away, because the first question is still worth
/// being able to ask.
struct PositionHistoryView: View {
    let itemID: String

    @Environment(AppEnvironment.self) private var environment
    @State private var entries: [ProgressJournalEntry] = []
    @State private var sessions: [ListeningSession] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView()
            } else if sessions.isEmpty && entries.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: Text(L("No history yet")),
                    message: Text(L("Each time you listen appears here, on every device."))
                )
            } else {
                List {
                    if sessions.isEmpty {
                        Section {
                            Text(L("Nothing long enough to count as a listen yet."))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    } else {
                        ForEach(sessions) { session in
                            sessionRow(session)
                        }
                    }

                    Section {
                        NavigationLink {
                            PositionMarksView(entries: entries, itemID: itemID)
                        } label: {
                            Label(L("Position marks"), systemImage: "mappin.and.ellipse")
                        }
                    } footer: {
                        Text(L("Every individual position this book has been at, including ones from other devices. Useful when two devices disagree."))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(Text(L("Listening history")))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // A wider window than the conflict prompt needs: sessions are only
            // meaningful across weeks.
            entries = await environment.sync.history(itemID: itemID, limit: 500)
            sessions = ListeningSessionBuilder().sessions(from: entries)
            isLoading = false
        }
    }

    private func sessionRow(_ session: ListeningSession) -> some View {
        Button {
            Task { await environment.resume(itemID: itemID, at: session.endPosition) }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: Self.when(session))
                        .font(Typography.emphasisedBody)
                        .foregroundStyle(Palette.primaryText)
                    Spacer(minLength: Spacing.s)
                    Text(verbatim: Format.duration(session.secondsListened))
                        .font(Typography.duration)
                        .foregroundStyle(Palette.accent)
                }

                HStack(spacing: Spacing.xs) {
                    Text(verbatim: PlaybackController.timecode(session.startPosition))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(verbatim: PlaybackController.timecode(session.endPosition))
                    if session.finishedHere {
                        Text(L("Finished"))
                            .foregroundStyle(Palette.accent)
                    }
                }
                .font(Typography.timecode)
                .foregroundStyle(Palette.secondaryText)

                // Only worth saying when it was not all one device — on a
                // single phone the name is the same on every row and adds
                // nothing but height.
                if session.deviceLabels.count > 1 {
                    Text(verbatim: session.deviceLabels.joined(separator: ", "))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(.vertical, Spacing.hair)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("Plays from where this listen ended"))
    }

    /// "Tuesday 21 October, 8:12–8:54 pm" — the day matters as much as the
    /// clock, because the question is usually "when did I last pick this up?"
    static func when(_ session: ListeningSession) -> String {
        let day = session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let from = session.startedAt.formatted(date: .omitted, time: .shortened)
        let to = session.endedAt.formatted(date: .omitted, time: .shortened)
        return from == to ? "\(day), \(from)" : "\(day), \(from) – \(to)"
    }
}

/// The raw journal: every position, where it came from, and whether it synced.
struct PositionMarksView: View {
    let entries: [ProgressJournalEntry]
    let itemID: String

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            ForEach(entries) { entry in
                Button {
                    guard let seconds = entry.position.currentTime else { return }
                    Task { await environment.resume(itemID: itemID, at: seconds) }
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
                .accessibilityHint(L("Plays from this position"))
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text(L("Position marks")))
        .navigationBarTitleDisplayMode(.inline)
    }
}
