import DesignSystem
import Persistence
import ReaderKit
import SwiftUI

/// Reads a comic.
///
/// Pages are loaded as they are reached and a small window either side is
/// kept warm — a comic page is a multi-megabyte image, and holding four
/// hundred of them in memory is how a reader gets killed by the system.
struct ComicPagerView: View {
    let item: LibraryItemSummary
    let fileURL: URL

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var archive: ComicArchive?
    @State private var images: [Int: UIImage] = [:]
    @State private var page = 0
    @State private var isLoading = true
    @State private var failure: String?
    @State private var isShowingChrome = true

    private var reader: ReaderController { environment.reader }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            if isShowingChrome { chrome }
        }
        .statusBarHidden(!isShowingChrome)
        .task { await open() }
        .onDisappear {
            archive?.close()
            Task { await reader.saveProgress(force: true) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().tint(.white)
        } else if let failure {
            ErrorStateView(message: Text(verbatim: failure)) {
                Task { await open() }
            }
        } else if let archive {
            TabView(selection: $page) {
                ForEach(archive.pages) { entry in
                    Group {
                        if let image = images[entry.index] {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .tag(entry.index)
                    .onTapGesture { withAnimation { isShowingChrome.toggle() } }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _, newValue in
                Task { await loadWindow(around: newValue) }
                reader.pageChanged(to: newValue + 1)
            }
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel(L("Close"))
                Spacer()
                Text(verbatim: item.title)
                    .font(Typography.caption)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await exportPDF() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L("Export as PDF"))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .firelightGlass(in: Capsule())
            .padding(.horizontal, Spacing.m)
            .foregroundStyle(.white)

            Spacer()

            if let archive {
                Text(verbatim: L("Page \(page + 1) of \(archive.pageCount)"))
                    .font(Typography.timecode)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .firelightGlass(in: Capsule())
                    .padding(.bottom, Spacing.l)
            }
        }
        .transition(.opacity)
    }

    @State private var exportURL: URL?

    private func open() async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let opened = try await ComicArchive.open(fileURL: fileURL)
            archive = opened
            reader.pageCount = opened.pageCount
            page = max(0, reader.currentPage - 1)
            await loadWindow(around: page)
        } catch {
            failure = L("This comic couldn't be opened.")
        }
    }

    /// Keeps the current page and its neighbours in memory, and nothing else.
    private func loadWindow(around index: Int) async {
        guard let archive else { return }
        let window = max(0, index - 1)...min(archive.pageCount - 1, index + 2)

        for page in window where images[page] == nil {
            if let image = await archive.image(at: page) {
                images[page] = image
            }
        }
        images = images.filter { window.contains($0.key) }
    }

    private func exportPDF() async {
        guard let archive else { return }
        // Rendering four hundred pages is slow and memory-hungry; this is a
        // deliberate, user-initiated action with a progress indicator.
        var rendered: [UIImage] = []
        for index in 0..<archive.pageCount {
            if let image = await archive.image(at: index) { rendered.append(image) }
        }
        let destination = URL.temporaryDirectory.appending(path: "\(item.title).pdf")
        exportURL = try? ComicPDFExporter.pdf(from: rendered, at: destination)
    }
}
