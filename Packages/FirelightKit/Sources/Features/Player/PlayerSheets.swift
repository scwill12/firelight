import ABSKit
import DesignSystem
import PlaybackKit
import SwiftUI

/// Sleep timer options.
struct SleepTimerSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private var player: PlaybackController { environment.player }

    var body: some View {
        NavigationStack {
            List {
                if let remaining = player.sleepRemaining {
                    Section {
                        LabeledContent {
                            Text(verbatim: PlaybackController.timecode(remaining))
                                .monospacedDigit()
                        } label: {
                            Text(L("Time left"))
                        }
                        Button(L("Add 5 minutes")) { player.extendSleepTimer() }
                        Button(role: .destructive) {
                            player.setSleepTimer(.off)
                            dismiss()
                        } label: {
                            Text(L("Turn off"))
                        }
                    } footer: {
                        Text(L("Shake your phone to add five minutes without unlocking it. The volume fades over the last 30 seconds."))
                    }
                }

                Section {
                    Button {
                        player.setSleepTimer(.endOfChapter)
                        dismiss()
                    } label: {
                        LabeledContent {
                            Text(verbatim: PlaybackController.timecode(player.timeRemainingInChapter))
                                .foregroundStyle(Palette.secondaryText)
                        } label: {
                            Text(L("End of this chapter"))
                        }
                    }
                    .disabled(player.chapters.isEmpty)

                    ForEach(SleepTimerMode.durationOptions, id: \.self) { option in
                        Button {
                            player.setSleepTimer(.duration(option))
                            dismiss()
                        } label: {
                            Text(verbatim: minutesLabel(option))
                        }
                    }
                } header: {
                    Text(L("Stop playing after"))
                }
            }
            .navigationTitle(Text(L("Sleep timer")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func minutesLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 && minutes % 60 == 0
            ? L("\(minutes / 60) hours")
            : L("\(minutes) minutes")
    }
}

/// Playback speed.
struct SpeedSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private var player: PlaybackController { environment.player }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.xl) {
                Text(verbatim: player.rate.description)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel(L("Speed \(player.rate.description)"))

                HStack(spacing: Spacing.xl) {
                    Button {
                        player.setRate(player.rate.stepped(by: -1))
                        Haptics.selection()
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.largeTitle)
                    }
                    .accessibilityLabel(L("Slower"))
                    .disabled(player.rate.value <= PlaybackRate.minimum)

                    Button {
                        player.setRate(player.rate.stepped(by: 1))
                        Haptics.selection()
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.largeTitle)
                    }
                    .accessibilityLabel(L("Faster"))
                    .disabled(player.rate.value >= PlaybackRate.maximum)
                }
                .foregroundStyle(Palette.accent)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: Spacing.m) {
                    ForEach(PlaybackRate.presets, id: \.self) { preset in
                        Button {
                            player.setRate(preset)
                            Haptics.selection()
                        } label: {
                            Text(verbatim: preset.description)
                                .font(Typography.emphasisedBody)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.s)
                                .firelightGlass(in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(preset == player.rate ? Palette.accent : Palette.primaryText)
                    }
                }
                .padding(.horizontal, Spacing.l)

                Text(L("Firelight remembers a speed for each book."))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)

                Spacer()
            }
            .padding(.top, Spacing.xl)
            .navigationTitle(Text(L("Speed")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Saved positions.
struct BookmarksSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var newNote = ""

    private var player: PlaybackController { environment.player }

    var body: some View {
        NavigationStack {
            Group {
                if player.bookmarks.isEmpty {
                    EmptyStateView(
                        systemImage: "bookmark",
                        title: Text(L("No bookmarks yet")),
                        message: Text(L("Save a spot and it syncs to Audiobookshelf."))
                    )
                } else {
                    List {
                        ForEach(player.bookmarks.sorted { $0.time < $1.time }) { bookmark in
                            Button {
                                player.seek(to: bookmark.time)
                                dismiss()
                            } label: {
                                LabeledContent {
                                    Text(verbatim: PlaybackController.timecode(bookmark.time))
                                        .font(Typography.timecode)
                                        .foregroundStyle(Palette.secondaryText)
                                } label: {
                                    Text(verbatim: bookmark.title ?? L("Bookmark"))
                                        .foregroundStyle(Palette.primaryText)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await player.deleteBookmark(bookmark) }
                                } label: {
                                    Label(L("Delete"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text(L("Bookmarks")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await player.addBookmark(title: nil) }
                    } label: {
                        Label(L("Add here"), systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } }
            }
            .task { await player.loadBookmarks() }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The chapter list.
///
/// The one thing an audiobook listener reaches for that a music player has no
/// equivalent of: "which chapter am I in, and take me to another one."
struct ChaptersSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private var player: PlaybackController { environment.player }

    var body: some View {
        NavigationStack {
            Group {
                if player.chapters.isEmpty {
                    EmptyStateView(
                        systemImage: "list.bullet.indent",
                        title: Text(L("No chapters")),
                        message: Text(L("This book doesn't have chapter marks on the server."))
                    )
                } else {
                    chapterList
                }
            }
            .navigationTitle(Text(L("Chapters")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { timeDisplayPicker }
        }
        // Opens large: this is a list you scroll, and a medium sheet with a
        // control pinned under it left room for barely two chapters.
        .presentationDetents([.large, .medium])
    }

    private var chapterList: some View {
        // Opens on the chapter you are in rather than at the top, which for a
        // forty-chapter book is the difference between useful and not.
        ScrollViewReader { proxy in
            List(player.chapters.chapters) { chapter in
                row(for: chapter)
                    .id(chapter.id)
            }
            .listStyle(.plain)
            .onAppear {
                guard let current = player.currentChapter else { return }
                proxy.scrollTo(current.id, anchor: .center)
            }
        }
    }

    private func row(for chapter: ABSChapter) -> some View {
        let isCurrent = player.currentChapter?.id == chapter.id
        return Button {
            player.seek(to: chapter.start)
            dismiss()
        } label: {
            HStack(spacing: Spacing.m) {
                // A playing indicator rather than a checkmark: this is where
                // you are, not something you ticked off.
                Image(systemName: isCurrent ? "speaker.wave.2.fill" : "circle.dotted")
                    .foregroundStyle(isCurrent ? Palette.accent : Palette.secondaryText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: Spacing.hair) {
                    Text(verbatim: chapter.title ?? L("Chapter"))
                        .font(isCurrent ? Typography.emphasisedBody : Typography.body)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(2)
                    Text(verbatim: Format.duration(chapter.duration))
                        .font(Typography.duration)
                        .foregroundStyle(Palette.secondaryText)
                }

                Spacer(minLength: Spacing.s)

                Text(verbatim: PlaybackController.timecode(chapter.start))
                    .font(Typography.timecode)
                    .foregroundStyle(Palette.secondaryText)
            }
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isCurrent ? Palette.accent.opacity(0.10) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// One compact row. The explanation that used to sit here was three lines
    /// tall and pushed the chapters off the screen; the control says what it
    /// does on its own.
    private var timeDisplayPicker: some View {
        Picker(
            selection: Binding(
                get: { player.timeDisplay },
                set: { player.setTimeDisplay($0) }
            )
        ) {
            Text(L("Time in book")).tag(TimeDisplay.book)
            Text(L("Time in chapter")).tag(TimeDisplay.chapter)
        } label: {
            Text(L("Time shown"))
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .background(.bar)
    }
}
