import DesignSystem
import DownloadKit
import SwiftUI

/// What is on the device, and how to get rid of it.
struct StorageView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var sortBySize = true

    private var downloads: DownloadsController { environment.downloads }

    private var sorted: [DownloadSummary] {
        sortBySize
            ? downloads.downloads.sorted { $0.bytesDownloaded > $1.bytesDownloaded }
            : downloads.downloads.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(verbatim: StorageFormatter.string(fromBytes: downloads.totalBytes))
                        .foregroundStyle(Palette.accent)
                } label: {
                    Text(L("Downloaded"))
                }
            } footer: {
                Text(L("Downloads live in Firelight's own storage and are excluded from iCloud backups."))
            }

            Section {
                Toggle(L("Wi-Fi only"), isOn: Binding(
                    get: { downloads.rules.wifiOnly },
                    set: { downloads.rules.wifiOnly = $0 }
                ))
                Toggle(L("Download the next book in a series"), isOn: Binding(
                    get: { downloads.rules.isAutoDownloadEnabled },
                    set: { downloads.rules.isAutoDownloadEnabled = $0 }
                ))
                Toggle(L("Remove finished books"), isOn: Binding(
                    get: { downloads.rules.isAutoRemoveEnabled },
                    set: { downloads.rules.isAutoRemoveEnabled = $0 }
                ))
                if downloads.rules.isAutoRemoveEnabled {
                    Stepper(
                        value: Binding(
                            get: { downloads.rules.removeFinishedAfterDays },
                            set: { downloads.rules.removeFinishedAfterDays = $0 }
                        ),
                        in: 1...90
                    ) {
                        Text(L("After \(downloads.rules.removeFinishedAfterDays) days"))
                    }
                }
            } header: {
                Text(L("Automatic"))
            } footer: {
                Text(L("The next book is fetched once you're 80% through the current one."))
            }

            Section {
                if sorted.isEmpty {
                    Text(L("Nothing downloaded yet"))
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(sorted) { download in
                        row(download)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await downloads.remove(itemID: download.itemID) }
                                } label: {
                                    Label(L("Delete"), systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text(L("Downloads"))
                    Spacer()
                    Picker(L("Sort"), selection: $sortBySize) {
                        Text(L("Size")).tag(true)
                        Text(L("Title")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }
        }
        .navigationTitle(Text(L("Storage")))
        .navigationBarTitleDisplayMode(.inline)
        .task { await downloads.reload() }
    }

    private func row(_ download: DownloadSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            LabeledContent {
                Text(verbatim: StorageFormatter.string(fromBytes: download.bytesDownloaded))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: download.title)
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                    if let author = download.author {
                        Text(verbatim: author)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            switch download.state {
            case .downloading(let fraction), .paused(let fraction):
                ProgressView(value: max(fraction, download.fraction)).tint(Palette.accent)
            case .queued:
                Text(L("Waiting…")).font(Typography.caption).foregroundStyle(Palette.secondaryText)
            case .failed(let reason):
                Text(verbatim: reason).font(Typography.caption).foregroundStyle(Palette.destructive)
            case .downloaded, .notDownloaded:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
