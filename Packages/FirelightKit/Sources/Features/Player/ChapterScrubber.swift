import ABSKit
import DesignSystem
import PlaybackKit
import SwiftUI

/// The scrubber: position within the chapter, the chapter marks, and the whole
/// book underneath.
///
/// Chapter-aware because that is how people navigate an audiobook — "back to
/// the start of this chapter" is a far more common intent than "to 6:14:22".
struct ChapterScrubber: View {
    let position: TimeInterval
    /// Where the bar starts in book time. Zero in book mode; the chapter's
    /// start in chapter mode, where the bar spans only the chapter.
    let scopeStart: TimeInterval
    /// How much book time the bar spans.
    let scopeDuration: TimeInterval
    let chapters: ChapterTimeline
    /// Marks are only meaningful when the bar covers more than one chapter.
    let showsChapterMarks: Bool
    let accent: Color
    let onScrub: (TimeInterval) -> Void
    /// Tapping the clock swaps chapter time for book time.
    let onToggleScope: () -> Void

    @State private var dragPosition: TimeInterval?
    @State private var lastHapticChapter: Int?

    private var displayPosition: TimeInterval { dragPosition ?? position }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(accent.opacity(0.22))
                        .frame(height: 6)

                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, geometry.size.width * fraction), height: 6)

                    // Chapter marks, so you can see what you are scrubbing past.
                    if showsChapterMarks {
                        ForEach(chapters.chapters) { chapter in
                            if let x = markOffset(for: chapter, width: geometry.size.width) {
                                Capsule()
                                    .fill(accent.opacity(0.55))
                                    .frame(width: 2, height: 12)
                                    .offset(x: x)
                            }
                        }
                    }

                    Circle()
                        .fill(accent)
                        .frame(width: dragPosition == nil ? 14 : 20)
                        .offset(x: max(0, geometry.size.width * fraction - (dragPosition == nil ? 7 : 10)))
                        .animation(.easeOut(duration: 0.12), value: dragPosition == nil)
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: geometry.size.width))
            }
            .frame(height: 24)

            Button(action: onToggleScope) {
                HStack {
                    Text(verbatim: PlaybackController.timecode(elapsed))
                    Spacer()
                    Text(verbatim: scopeLabel)
                        .font(Typography.caption)
                        .opacity(0.75)
                    Spacer()
                    Text(verbatim: "−\(PlaybackController.timecode(remaining))")
                }
                .font(Typography.timecode)
                .foregroundStyle(accent.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(showsChapterMarks ? L("Position in book") : L("Position in chapter"))
        .accessibilityValue(PlaybackController.timecode(elapsed))
        .accessibilityAction(named: Text(L("Switch between chapter and book time")), onToggleScope)
        .accessibilityAdjustableAction { direction in
            let step: TimeInterval = 30
            switch direction {
            case .increment: onScrub(min(scopeStart + scopeDuration, position + step))
            case .decrement: onScrub(max(scopeStart, position - step))
            @unknown default: break
            }
        }
    }

    private var elapsed: TimeInterval { max(0, displayPosition - scopeStart) }

    private var remaining: TimeInterval {
        max(0, scopeStart + scopeDuration - displayPosition)
    }

    private var scopeLabel: String {
        showsChapterMarks ? L("Book") : L("Chapter")
    }

    private var fraction: Double {
        guard scopeDuration > 0 else { return 0 }
        return min(max(elapsed / scopeDuration, 0), 1)
    }

    /// A mark's x position, or nil when it falls outside the bar.
    private func markOffset(for chapter: ABSChapter, width: CGFloat) -> CGFloat? {
        guard scopeDuration > 0, chapter.start > scopeStart else { return nil }
        let into = (chapter.start - scopeStart) / scopeDuration
        guard into > 0, into < 1 else { return nil }
        return width * into - 1
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scopeDuration > 0, width > 0 else { return }
                let target = scopeStart + min(max(value.location.x / width, 0), 1) * scopeDuration
                dragPosition = target
                // A tick as each chapter mark passes under the thumb.
                if let index = chapters.index(at: target), index != lastHapticChapter {
                    lastHapticChapter = index
                    Haptics.impact(.chapterMark)
                }
            }
            .onEnded { _ in
                if let dragPosition { onScrub(dragPosition) }
                dragPosition = nil
                lastHapticChapter = nil
            }
    }
}
