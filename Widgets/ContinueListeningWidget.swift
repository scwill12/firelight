import AppIntents
import DesignSystem
import Persistence
import PlaybackKit
import SwiftUI
import WidgetKit

/// What you are in the middle of.
///
/// Reads the snapshot the app writes to the shared container — a widget runs
/// in its own process with a few milliseconds to draw, so it never opens the
/// database.
struct ContinueListeningWidget: Widget {
    let kind = "ContinueListening"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueListeningProvider()) { entry in
            ContinueListeningView(entry: entry)
                .containerBackground(Palette.background, for: .widget)
        }
        .configurationDisplayName("Continue")
        .description("Pick up where you left off.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryInline, .accessoryCircular,
        ])
    }
}

struct ContinueListeningEntry: TimelineEntry {
    enum Content: Equatable {
        /// No server has been added yet.
        case notConfigured
        /// A server is set up but nothing is in progress.
        case nothingInProgress
        case playing(NowPlayingSnapshot)
    }

    let date: Date
    let content: Content
}

struct ContinueListeningProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueListeningEntry {
        ContinueListeningEntry(date: .now, content: .playing(Self.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueListeningEntry) -> Void) {
        completion(currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueListeningEntry>) -> Void) {
        let now = Date.now
        guard case .playing(let snapshot) = currentEntry(at: now).content, snapshot.isPlaying else {
            // Paused or idle: nothing moves, so there is nothing to schedule.
            completion(Timeline(entries: [currentEntry(at: now)], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        // While playing, the position advances on its own. A handful of
        // entries keeps the bar moving without waking the app every minute.
        let entries = stride(from: 0, through: 50 * 60, by: 10 * 60).map { offset -> ContinueListeningEntry in
            let date = now.addingTimeInterval(TimeInterval(offset))
            return ContinueListeningEntry(date: date, content: .playing(snapshot.projected(to: date)))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(55 * 60))))
    }

    private func currentEntry(at date: Date) -> ContinueListeningEntry {
        guard SharedState.hasConfiguredServer else {
            return ContinueListeningEntry(date: date, content: .notConfigured)
        }
        guard let snapshot = SharedState.nowPlaying else {
            return ContinueListeningEntry(date: date, content: .nothingInProgress)
        }
        return ContinueListeningEntry(date: date, content: .playing(snapshot.projected(to: date)))
    }

    static let sample = NowPlayingSnapshot(
        itemID: "preview",
        title: "The Wind in the Willows",
        author: "Kenneth Grahame",
        chapterTitle: "The River Bank",
        position: 4_200,
        duration: 21_600,
        isPlaying: true
    )
}

struct ContinueListeningView: View {
    let entry: ContinueListeningEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.content {
        case .notConfigured:
            message(icon: "server.rack", text: "Add your server in Firelight.")
        case .nothingInProgress:
            message(icon: "books.vertical", text: "Nothing in progress.")
        case .playing(let snapshot):
            switch family {
            case .accessoryInline:
                Text(verbatim: snapshot.title)
            case .accessoryCircular:
                ProgressView(value: snapshot.fraction) {
                    Image(systemName: "headphones")
                }
                .progressViewStyle(.circular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: snapshot.title).font(.headline).lineLimit(1)
                    Text(verbatim: snapshot.chapterTitle ?? snapshot.author ?? "")
                        .font(.caption).lineLimit(1)
                    ProgressView(value: snapshot.fraction)
                }
            default:
                full(snapshot)
            }
        }
    }

    private func full(_ snapshot: NowPlayingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: snapshot.title)
                .font(Typography.itemTitle)
                .foregroundStyle(Palette.primaryText)
                .lineLimit(2)

            if let subtitle = snapshot.chapterTitle ?? snapshot.author {
                Text(verbatim: subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ProgressView(value: snapshot.fraction)
                .tint(Palette.accent)

            HStack {
                Text(verbatim: "\(Int(snapshot.timeRemaining / 60)) min left")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                if family == .systemMedium {
                    // The system runs this in the app when it owns the audio
                    // session, so the button really does control playback.
                    Button(intent: TogglePlaybackIntent()) {
                        Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func message(icon: String, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Palette.accent)
            Text(text)
                .font(Typography.itemSubtitle)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Days in a row with some listening.
struct StreakWidget: Widget {
    let kind = "ListeningStreak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakView(days: entry.days)
                .containerBackground(Palette.background, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Days in a row you've listened or read.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct StreakEntry: TimelineEntry {
    let date: Date
    let days: Int
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry { StreakEntry(date: .now, days: 7) }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: .now, days: SharedState.listeningStreak))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(date: .now, days: SharedState.listeningStreak)
        // A streak only changes at midnight, so that is when to look again.
        let midnight = Calendar.current.nextDate(
            after: .now, matching: DateComponents(hour: 0, minute: 1), matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct StreakView: View {
    let days: Int
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(verbatim: "\(days) day streak")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.caption)
                Text(verbatim: "\(days)").font(.headline)
            }
        default:
            VStack(spacing: Spacing.xs) {
                Image(systemName: "flame.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Palette.accent)
                Text(verbatim: "\(days)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.primaryText)
                Text(days == 1 ? "day in a row" : "days in a row")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(days == 1 ? "1 day streak" : "\(days) day streak")
        }
    }
}
