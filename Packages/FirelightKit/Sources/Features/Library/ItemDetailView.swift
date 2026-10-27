import DesignSystem
import DownloadKit
import Persistence
import ReaderKit
import SwiftUI

/// One item: its cover, what it is, and where you are in it.
///
/// Playback arrives in Phase 3 and reading in Phase 6, so this screen does not
/// pretend to offer either yet.
struct ItemDetailView: View {
    let itemID: String

    @Environment(AppEnvironment.self) private var environment
    @State private var item: LibraryItemSummary?
    @State private var isLoading = true
    @State private var downloadError: String?
    @State private var isShowingReader = false
    @State private var isShowingExport = false
    @State private var isShowingFollowAlong = false
    @State private var shareFiles: StagedShare?
    @State private var isPreparingShare = false

    /// Small on purpose. The cover used to fill the screen and push Play below
    /// the fold, so starting a book you had just tapped meant scrolling first.
    private static let coverWidth: CGFloat = 124

    var body: some View {
        Group {
            if let item, item.mediaType == "podcast" {
                PodcastShowView(item: item)
            } else if let item {
                content(item)
            } else if isLoading {
                LoadingStateView()
            } else {
                EmptyStateView(
                    systemImage: "questionmark.folder",
                    title: Text(L("Not in your library")),
                    message: Text(L("This item isn't in the cached library any more."))
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // Handoff: picking this up on another device lands on the same book.
        .userActivity(HandoffActivity.itemType, isActive: item != nil) { activity in
            guard let item, let serverID = environment.session.activeServer?.id else { return }
            activity.title = item.title
            activity.isEligibleForHandoff = true
            activity.addUserInfoEntries(from: HandoffActivity.userInfo(
                for: HandoffActivity.Payload(
                    serverID: serverID,
                    itemID: item.id,
                    position: environment.player.itemID == item.id ? environment.player.position : nil,
                    title: item.title
                )
            ))
        }
        .fullScreenCover(isPresented: $isShowingReader) {
            if let item {
                ReaderView(item: item)
            }
        }
        .sheet(isPresented: $isShowingExport) {
            if let item {
                ExportSheet(item: item)
            }
        }
        .sheet(item: $shareFiles) { staged in
            ShareSheet(items: staged.urls)
        }
        .sheet(isPresented: $isShowingFollowAlong) {
            if let item {
                FollowAlongSheet(itemID: item.id, title: item.title)
            }
        }
        .task {
            item = await environment.library.item(id: itemID)
            isLoading = false
            environment.followAlong.load(itemID: itemID)
        }
    }

    private func content(_ item: LibraryItemSummary) -> some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                header(item)

                if item.isStarted || item.isFinished {
                    progress(item)
                }

                playButton(item)
                downloadRow(item)

                facts(item)

                followAlongRow(item)

                NavigationLink {
                    PositionHistoryView(itemID: item.id)
                } label: {
                    Label(L("Listening history"), systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.s)
                }
                .padding(.horizontal, Spacing.l)

                if let summary = item.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(L("About"))
                            .font(Typography.sectionTitle)
                            .foregroundStyle(Palette.primaryText)
                        Text(verbatim: summary)
                            .font(Typography.body)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.l)
                }
            }
            .padding(.bottom, Spacing.xxl)
        }
    }

    /// Cover, title and length side by side, so everything that decides
    /// whether to press Play is on screen at the same time as Play.
    private func header(_ item: LibraryItemSummary) -> some View {
        HStack(alignment: .top, spacing: Spacing.l) {
            CoverImage(itemID: item.id, title: item.title)
                .frame(
                    width: Self.coverWidth,
                    height: CoverArt.height(forWidth: Self.coverWidth)
                )
                .shadow(
                    color: .black.opacity(Elevation.cardShadowOpacity),
                    radius: Elevation.cardShadowRadius,
                    y: Elevation.cardShadowY
                )

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verbatim: item.title)
                    .font(Typography.detailTitle)
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(3)

                if let subtitle = item.subtitle {
                    Text(verbatim: subtitle)
                        .font(Typography.itemSubtitle)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                }
                if let author = item.author {
                    Text(verbatim: author)
                        .font(Typography.itemSubtitle)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: Spacing.s)

                if item.duration > 0 {
                    Text(verbatim: Format.duration(item.duration))
                        .font(Typography.duration)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: CoverArt.height(forWidth: Self.coverWidth),
                alignment: .leading
            )
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func playButton(_ item: LibraryItemSummary) -> some View {
        if item.hasAudio {
            Button {
                Task { await environment.play(item: item) }
            } label: {
                Label(
                    item.isStarted ? L("Resume") : L("Play"),
                    systemImage: "play.fill"
                )
                .font(Typography.emphasisedBody)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.m)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .padding(.horizontal, Spacing.l)
        }

        if item.hasEbook {
            Button {
                isShowingExport = true
            } label: {
                Label(L("Export or send to Kindle"), systemImage: "square.and.arrow.up")
                    .font(Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.s)
            }
            .padding(.horizontal, Spacing.l)

            Button {
                isShowingReader = true
            } label: {
                Label(L("Read"), systemImage: "book")
                    .font(Typography.emphasisedBody)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.m)
            }
            // Bordered when there is also audio, so the two buttons do not
            // compete; prominent when reading is the only thing to do.
            .buttonStyle(.bordered)
            .tint(Palette.accent)
            .padding(.horizontal, Spacing.l)
        }
    }

    /// Copies the downloaded files somewhere a recipient can make sense of
    /// them, then hands them to the share sheet — AirDrop, Files, Messages,
    /// whatever the person has.
    private func prepareShare(_ item: LibraryItemSummary) async {
        isPreparingShare = true
        defer { isPreparingShare = false }

        let tracks = await environment.downloads.localTracks(forItemID: item.id, episodeID: nil)
        guard !tracks.isEmpty else { return }

        // Anything staged for an earlier share is a second copy of an
        // audiobook sitting in tmp; clear it before making another.
        SharedDownload.clearStaged()
        guard let urls = try? SharedDownload.stage(
            title: item.title,
            sources: tracks.map(\.url)
        ), !urls.isEmpty else { return }

        shareFiles = StagedShare(urls: urls)
    }

    /// Where to set up following along, for someone who has not pressed play
    /// yet. The same sheet is a tap away inside the player.
    @ViewBuilder
    private func followAlongRow(_ item: LibraryItemSummary) -> some View {
        if environment.followAlong.isEnabled, item.hasAudio {
            Button {
                isShowingFollowAlong = true
            } label: {
                LabeledContent {
                    Text(verbatim: followAlongValue(item))
                        .foregroundStyle(Palette.secondaryText)
                } label: {
                    Label(L("Following along"), systemImage: "book.pages")
                }
                .padding(.vertical, Spacing.s)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.l)
        }
    }

    private func followAlongValue(_ item: LibraryItemSummary) -> String {
        guard environment.followAlong.edition?.isUsable == true,
              let edition = environment.followAlong.edition
        else { return L("Not set") }
        return edition.unit == .location
            ? L("\(edition.lastPosition) locations")
            : L("\(edition.lastPosition) pages")
    }

    @ViewBuilder
    private func downloadRow(_ item: LibraryItemSummary) -> some View {
        if item.hasAudio {
            let state = environment.downloads.state(forItemID: item.id)
            HStack(spacing: Spacing.m) {
                switch state {
                case .notDownloaded, .failed:
                    Button {
                        Task { downloadError = await environment.downloads.download(item: item) }
                    } label: {
                        Label(L("Download"), systemImage: "arrow.down.circle")
                    }
                case .queued:
                    Label(L("Waiting…"), systemImage: "clock")
                        .foregroundStyle(Palette.secondaryText)
                case .downloading(let fraction), .paused(let fraction):
                    ProgressView(value: fraction)
                        .tint(Palette.accent)
                    Button(L("Stop")) {
                        Task { await environment.downloads.remove(itemID: item.id) }
                    }
                case .downloaded(let bytes):
                    Label(
                        L("Downloaded · \(StorageFormatter.string(fromBytes: bytes))"),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(Palette.accent)
                    Spacer()
                    Button {
                        Task { await prepareShare(item) }
                    } label: {
                        if isPreparingShare {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isPreparingShare)
                    .accessibilityLabel(L("Share the downloaded files"))
                    Button(role: .destructive) {
                        Task { await environment.downloads.remove(itemID: item.id) }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .font(Typography.body)
            .padding(.horizontal, Spacing.l)

            if case .failed(let reason) = state {
                Text(verbatim: reason)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.destructive)
                    .padding(.horizontal, Spacing.l)
            }
            if let downloadError {
                Text(verbatim: downloadError)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.notice)
                    .padding(.horizontal, Spacing.l)
            }
        }
    }

    private func progress(_ item: LibraryItemSummary) -> some View {
        VStack(spacing: Spacing.xs) {
            ProgressView(value: item.isFinished ? 1 : item.progressFraction)
                .tint(Palette.accent)
            Text(verbatim: item.isFinished
                 ? L("Finished")
                 : L("\(Format.duration(item.remainingTime)) left"))
                .font(Typography.duration)
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .combine)
    }

    private func facts(_ item: LibraryItemSummary) -> some View {
        VStack(spacing: 0) {
            if let narrator = item.narrator {
                factRow(L("Narrated by"), narrator)
            }
            if let series = item.seriesName {
                factRow(L("Series"), series)
            }
            if item.duration > 0 {
                factRow(L("Length"), Format.duration(item.duration))
            }
            if item.numChapters > 0 {
                factRow(L("Chapters"), String(item.numChapters))
            }
            if let year = item.publishedYear.map(Format.publicationYear), !year.isEmpty {
                factRow(L("Published"), year)
            }
            if let format = item.ebookFormat, !format.isEmpty {
                factRow(L("Ebook"), format.uppercased())
            }
            if !item.genres.isEmpty {
                factRow(L("Genres"), item.genres.joined(separator: ", "))
            }
        }
        .padding(.horizontal, Spacing.l)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label)
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: Spacing.l)
            Text(verbatim: value)
                .font(Typography.body)
                .foregroundStyle(Palette.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Spacing.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.separator).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}


/// The staged files, identified so a sheet can be driven from them.
struct StagedShare: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.lastPathComponent).joined() }
}
