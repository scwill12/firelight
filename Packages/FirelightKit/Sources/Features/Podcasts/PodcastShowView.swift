import DesignSystem
import DownloadKit
import Persistence
import SwiftUI

/// One podcast: what it is, and every episode.
struct PodcastShowView: View {
    let item: LibraryItemSummary

    @Environment(AppEnvironment.self) private var environment
    @State private var filter: EpisodeFilter = .all

    private var podcasts: PodcastController { environment.podcasts }

    enum EpisodeFilter: String, CaseIterable {
        case all, unplayed, inProgress

        var title: String {
            switch self {
            case .all: L("All")
            case .unplayed: L("Unplayed")
            case .inProgress: L("In progress")
            }
        }
    }

    private var filtered: [EpisodeSummary] {
        switch filter {
        case .all: podcasts.episodes
        case .unplayed: podcasts.episodes.filter(\.isUnplayed)
        case .inProgress: podcasts.episodes.filter(\.isStarted)
        }
    }

    var body: some View {
        List {
            Section {
                header
            }

            Section {
                Toggle(L("Download new episodes automatically"), isOn: Binding(
                    get: { podcasts.autoDownloadEnabled },
                    set: { enabled in
                        Task { await podcasts.setAutoDownload(itemID: item.id, enabled: enabled) }
                    }
                ))
                Button {
                    Task { await podcasts.checkForNewEpisodes(itemID: item.id) }
                } label: {
                    Label(L("Check for new episodes"), systemImage: "arrow.clockwise")
                }
            } footer: {
                Text(L("Automatic downloads happen on the server, not on this device."))
            }

            Section {
                if filtered.isEmpty {
                    Text(podcasts.isLoading ? L("Loading episodes…") : L("No episodes here."))
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(filtered) { episode in
                        EpisodeRow(episode: episode) {
                            Task { await environment.play(episode: episode, showTitle: item.title) }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                environment.podcasts.enqueue(QueueEntry(
                                    itemID: episode.itemID,
                                    episodeID: episode.episodeID,
                                    title: episode.title,
                                    subtitle: item.title
                                ))
                                Haptics.success()
                            } label: {
                                Label(L("Up Next"), systemImage: "text.append")
                            }
                            .tint(Palette.accent)
                        }
                    }
                }
            } header: {
                Picker(L("Show"), selection: $filter) {
                    ForEach(EpisodeFilter.allCases, id: \.self) { option in
                        Text(verbatim: option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(Text(verbatim: item.title))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await podcasts.refresh(itemID: item.id) }
        .task { await podcasts.load(itemID: item.id) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            CoverImage(itemID: item.id, title: item.title)
                .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: item.title)
                    .font(Typography.itemTitle)
                    .lineLimit(2)
                if let author = podcasts.showAuthor ?? item.author {
                    Text(verbatim: author)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                Text(verbatim: L("\(podcasts.episodes.count) episodes"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EpisodeRow: View {
    let episode: EpisodeSummary
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.s) {
                    if episode.isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.accent)
                            .font(.caption)
                    } else if episode.isUnplayed {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 8, height: 8)
                    }
                    if let numbering = episode.numbering {
                        Text(verbatim: numbering)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    if let published = episode.publishedAt {
                        Text(verbatim: published.formatted(date: .abbreviated, time: .omitted))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }

                Text(verbatim: episode.title)
                    .font(Typography.emphasisedBody)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(2)

                if let subtitle = episode.subtitle {
                    Text(verbatim: subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.s) {
                    if episode.duration > 0 {
                        Text(verbatim: episode.isStarted
                             ? L("\(Format.duration(episode.remainingTime)) left")
                             : Format.duration(episode.duration))
                    }
                    if episode.sizeBytes > 0 {
                        Text(verbatim: StorageFormatter.string(fromBytes: episode.sizeBytes))
                    }
                }
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)

                if episode.isStarted {
                    ProgressView(value: episode.progressFraction)
                        .tint(Palette.accent)
                }
            }
            .padding(.vertical, Spacing.hair)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L("Plays this episode"))
    }
}

/// Up Next: books and episodes in one queue.
struct UpNextView: View {
    @Environment(AppEnvironment.self) private var environment

    private var podcasts: PodcastController { environment.podcasts }

    var body: some View {
        List {
            if podcasts.queue.isEmpty {
                Section {
                    Text(L("Nothing queued. Swipe an episode or a book to add it."))
                        .foregroundStyle(Palette.secondaryText)
                }
            } else {
                ForEach(podcasts.queue) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: entry.title)
                            .foregroundStyle(Palette.primaryText)
                            .lineLimit(1)
                        if let subtitle = entry.subtitle {
                            Text(verbatim: subtitle)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    for index in offsets { podcasts.remove(podcasts.queue[index]) }
                }
                .onMove { source, destination in
                    podcasts.move(from: source, to: destination)
                }
            }
        }
        .navigationTitle(Text(L("Up Next")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !podcasts.queue.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Clear")) { podcasts.clearQueue() }
                }
            }
        }
    }
}
