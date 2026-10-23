import ActivityKit
import AppIntents
import DesignSystem
import Persistence
import PlaybackKit
import SwiftUI
import WidgetKit

/// The Live Activity and the Dynamic Island.
///
/// The countdown is a `Text(timerInterval:)` rather than a number the app
/// pushes every second: the system animates it for free, and a Live Activity
/// that needs a push per second gets throttled into uselessness.
struct PlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Palette.background.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "headphones")
                        .font(.title3)
                        .foregroundStyle(Palette.accent)
                        .padding(.leading, Spacing.xs)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    remaining(context)
                        .font(Typography.timecode)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.trailing, Spacing.xs)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(verbatim: context.attributes.title)
                            .font(Typography.itemSubtitle)
                            .lineLimit(1)
                        if let chapter = context.state.chapterTitle {
                            Text(verbatim: chapter)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: Spacing.s) {
                        ProgressView(value: context.state.fraction)
                            .tint(Palette.accent)
                        controls(context)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "headphones" : "pause.fill")
                    .foregroundStyle(Palette.accent)
            } compactTrailing: {
                remaining(context)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "headphones")
                    .foregroundStyle(Palette.accent)
            }
            .keylineTint(Palette.accent)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<PlaybackActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: context.attributes.title)
                        .font(Typography.itemTitle)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    Text(verbatim: context.state.chapterTitle ?? context.attributes.author ?? "")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.m)
                remaining(context)
                    .font(Typography.timecode)
                    .foregroundStyle(Palette.secondaryText)
            }

            ProgressView(value: context.state.fraction)
                .tint(Palette.accent)

            controls(context)
        }
        .padding(Spacing.m)
    }

    private func controls(_ context: ActivityViewContext<PlaybackActivityAttributes>) -> some View {
        HStack(spacing: Spacing.xl) {
            Button(intent: SkipBackIntent()) {
                Image(systemName: "gobackward")
            }
            .accessibilityLabel("Skip back")

            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .accessibilityLabel(context.state.isPlaying ? "Pause" : "Play")

            Button(intent: SkipForwardIntent()) {
                Image(systemName: "goforward")
            }
            .accessibilityLabel("Skip forward")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
        .frame(maxWidth: .infinity)
    }

    /// Counts itself down while playing; a fixed figure when paused.
    @ViewBuilder
    private func remaining(_ context: ActivityViewContext<PlaybackActivityAttributes>) -> some View {
        if context.state.isPlaying {
            Text(timerInterval: Date.now...context.state.projectedFinish, countsDown: true)
                .monospacedDigit()
        } else {
            Text(verbatim: "\(Int(context.state.timeRemaining / 60)) min")
        }
    }
}
