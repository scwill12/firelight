import DesignSystem
import PlaybackKit
import ReaderKit
import SwiftUI

/// The full player.
///
/// Tinted from the cover, with every colour checked for contrast first, so a
/// dark cover can never produce unreadable controls.
struct PlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowingSleepTimer = false
    @State private var isShowingBookmarks = false
    @State private var isShowingSpeed = false
    @State private var isShowingChapters = false
    @State private var dragOffset: CGFloat = 0
    @State private var isShowingFollowAlong = false

    let namespace: Namespace.ID

    private var player: PlaybackController { environment.player }
    private var palette: CoverPalette { environment.coverPalette }

    var body: some View {
        ZStack {
            background
            content
        }
        .offset(y: dragOffset)
        // The player is a full-screen cover, which has no dismiss gesture of
        // its own — so the grabber was decoration and swiping down did
        // nothing. The cover and the artwork carry the gesture; the scrubber
        // and the buttons keep their own, because a child gesture wins.
        .gesture(dragToDismiss)
        .sheet(isPresented: $isShowingSleepTimer) { SleepTimerSheet() }
        .sheet(isPresented: $isShowingBookmarks) { BookmarksSheet() }
        .sheet(isPresented: $isShowingSpeed) { SpeedSheet() }
        .sheet(isPresented: $isShowingChapters) { ChaptersSheet() }
        .sheet(isPresented: $isShowingFollowAlong) {
            if let itemID = player.itemID {
                FollowAlongSheet(itemID: itemID, title: player.title)
            }
        }
        .onChange(of: player.itemID, initial: true) {
            guard let itemID = player.itemID else { return }
            environment.followAlong.load(itemID: itemID)
        }
        // Shake to extend the sleep timer — the one gesture you can manage
        // half asleep.
        .onShake {
            guard player.sleepRemaining != nil else { return }
            player.extendSleepTimer()
        }
    }

    /// Follows the finger down, and dismisses on a deliberate pull — either
    /// far enough, or fast enough that the flick was clearly meant.
    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let pulled = value.translation.height > 140
                let flicked = value.predictedEndTranslation.height > 320
                if pulled || flicked {
                    Haptics.impact(.chapterMark)
                    dismiss()
                    dragOffset = 0
                } else {
                    withAnimation(Motion.animation(reduceMotion: reduceMotion)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var background: some View {
        LinearGradient(
            colors: [palette.background.color, palette.background.color.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(Motion.animation(reduceMotion: reduceMotion), value: palette)
    }

    private var content: some View {
        VStack(spacing: Spacing.l) {
            grabber

            if let itemID = player.itemID {
                CoverImage(itemID: itemID, title: player.title)
                    .matchedGeometryEffect(id: itemID, in: namespace)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                    .padding(.horizontal, Spacing.xl)
            }

            titles

            if let failure = player.failure {
                Text(verbatim: failure)
                    .font(Typography.caption)
                    .foregroundStyle(palette.primaryText.color.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }

            ChapterScrubber(
                position: player.position,
                scopeStart: player.timeScope.start,
                scopeDuration: player.timeScope.duration,
                chapters: player.chapters,
                showsChapterMarks: player.timeDisplay == .book,
                accent: palette.accent.color,
                onScrub: { player.seek(to: $0) },
                onToggleScope: { player.toggleTimeDisplay() }
            )
            .padding(.horizontal, Spacing.xl)
            .animation(Motion.animation(reduceMotion: reduceMotion), value: player.timeDisplay)

            followAlongLine

            transport
            secondaryControls

            Spacer(minLength: Spacing.l)
        }
        .padding(.top, Spacing.s)
        .foregroundStyle(palette.primaryText.color)
    }

    /// Roughly where this would be in the listener's own copy.
    ///
    /// Only shown when they asked for it *and* told us how long their edition
    /// is. Tapping it is how they set or change that, which puts the control
    /// exactly where the question occurs to them.
    @ViewBuilder
    private var followAlongLine: some View {
        if environment.followAlong.isEnabled, player.itemID != nil {
            Button {
                isShowingFollowAlong = true
            } label: {
                Group {
                    if let position = environment.followAlong.position(progress: player.bookProgress) {
                        Text(verbatim: Self.label(for: position))
                    } else {
                        Label(L("Set up follow-along"), systemImage: "book.pages")
                    }
                }
                .font(Typography.duration)
                .foregroundStyle(palette.primaryText.color.opacity(0.7))
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// "About location 3,204 of 9,112". *About*, because it is an estimate and
    /// saying so once in the label is better than a footnote nobody reads.
    nonisolated static func label(for position: FollowAlongPosition) -> String {
        let value = Self.grouped(position.value)
        let total = Self.grouped(position.total)
        return position.unit == .location
            ? L("About location \(value) of \(total)")
            : L("About page \(value) of \(total)")
    }

    nonisolated static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private var grabber: some View {
        Capsule()
            .fill(palette.primaryText.color.opacity(0.3))
            .frame(width: 40, height: 5)
            .padding(.top, Spacing.s)
            // A bigger target than it looks: the grabber is the obvious place
            // to grab, and five points is not a handle.
            .padding(.vertical, Spacing.s)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L("Close the player"))
            .accessibilityAction { dismiss() }
            .onTapGesture { dismiss() }
    }

    private var titles: some View {
        VStack(spacing: Spacing.xs) {
            Text(verbatim: player.title)
                .font(Typography.itemTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // The chapter, then the author — in that order, because the
            // chapter is the thing that changes while you listen. The book
            // title was previously printed twice when the author was missing.
            if let chapter = player.currentChapter?.title, !chapter.isEmpty {
                Text(verbatim: chapter)
                    .font(Typography.itemSubtitle)
                    .foregroundStyle(palette.primaryText.color.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }

            if let author = player.author, !author.isEmpty {
                Text(verbatim: author)
                    .font(Typography.caption)
                    .foregroundStyle(palette.primaryText.color.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button { player.previousChapter() } label: {
                Image(systemName: "backward.end.fill").font(.title2)
            }
            .accessibilityLabel(L("Previous chapter"))
            .disabled(player.chapters.isEmpty)
            .frame(maxWidth: .infinity)

            Button { player.skipBackward() } label: {
                Image(systemName: "gobackward").font(.title)
                    .overlay {
                        Text(verbatim: String(Int(player.skipInterval.backward)))
                            .font(.system(size: 10, weight: .bold))
                            .offset(y: 1)
                    }
            }
            .accessibilityLabel(L("Skip back \(Int(player.skipInterval.backward)) seconds"))
            .frame(maxWidth: .infinity)

            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle()
                        .fill(palette.accent.color)
                        .frame(width: 72, height: 72)
                    if player.isBuffering {
                        ProgressView().tint(palette.background.color)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(palette.background.color)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }
            }
            .accessibilityLabel(player.isPlaying ? L("Pause") : L("Play"))
            .frame(maxWidth: .infinity)

            Button { player.skipForward() } label: {
                Image(systemName: "goforward").font(.title)
                    .overlay {
                        Text(verbatim: String(Int(player.skipInterval.forward)))
                            .font(.system(size: 10, weight: .bold))
                            .offset(y: 1)
                    }
            }
            .accessibilityLabel(L("Skip forward \(Int(player.skipInterval.forward)) seconds"))
            .frame(maxWidth: .infinity)

            Button { player.nextChapter() } label: {
                Image(systemName: "forward.end.fill").font(.title2)
            }
            .accessibilityLabel(L("Next chapter"))
            .disabled(player.chapters.isEmpty)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.l)
        .foregroundStyle(palette.primaryText.color)
    }

    private var secondaryControls: some View {
        HStack(spacing: 0) {
            secondaryButton(
                systemImage: "speedometer",
                caption: player.rate.description,
                label: L("Playback speed, \(player.rate.description)")
            ) { isShowingSpeed = true }

            secondaryButton(
                systemImage: "list.bullet.indent",
                caption: L("Chapters"),
                label: L("Chapters"),
                isHighlighted: false
            ) { isShowingChapters = true }
            .disabled(player.chapters.isEmpty)

            secondaryButton(
                systemImage: "bookmark",
                caption: L("Save"),
                label: L("Add a bookmark here")
            ) { Task { await player.addBookmark(title: nil) } }

            secondaryButton(
                systemImage: "list.bullet",
                caption: L("Marks"),
                label: L("Bookmarks")
            ) { isShowingBookmarks = true }

            secondaryButton(
                systemImage: player.sleepRemaining == nil ? "moon" : "moon.fill",
                caption: sleepLabel,
                label: L("Sleep timer"),
                isHighlighted: player.sleepRemaining != nil
            ) { isShowingSleepTimer = true }
        }
        .padding(.horizontal, Spacing.l)
        .foregroundStyle(palette.primaryText.color.opacity(0.85))
    }

    /// One of the five controls under the transport. They share the width
    /// equally so the row stays even at every Dynamic Type size, where a
    /// fixed gap used to push the outer two off the screen.
    private func secondaryButton(
        systemImage: String,
        caption: String,
        label: String,
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.hair) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(height: 24)
                Text(verbatim: caption)
                    .font(Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isHighlighted ? palette.accent.color : palette.primaryText.color.opacity(0.85))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var sleepLabel: String {
        guard let remaining = player.sleepRemaining else { return L("Sleep") }
        return PlaybackController.timecode(remaining)
    }
}

/// A compact player that stays above the tab bar.
struct MiniPlayer: View {
    @Environment(AppEnvironment.self) private var environment
    let namespace: Namespace.ID
    let onTap: () -> Void

    private var player: PlaybackController { environment.player }

    var body: some View {
        if let itemID = player.itemID {
            Button(action: onTap) {
                HStack(spacing: Spacing.m) {
                    CoverImage(itemID: itemID, title: player.title, cornerRadius: Radius.small)
                        .matchedGeometryEffect(id: itemID, in: namespace)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: player.title)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                        Text(verbatim: player.currentChapter?.title ?? PlaybackController.timecode(player.position))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(Palette.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying ? L("Pause") : L("Play"))
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.s)
                .firelightGlass(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(alignment: .bottom) {
                    ProgressView(value: player.bookProgress)
                        .tint(Palette.accent)
                        .scaleEffect(x: 1, y: 0.5, anchor: .bottom)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.m)
            .accessibilityElement(children: .contain)
        }
    }
}
