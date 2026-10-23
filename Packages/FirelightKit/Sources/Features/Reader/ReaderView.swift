import DesignSystem
import ConversionKit
import Persistence
import ReaderKit
import SwiftUI

/// The reading surface, whichever viewer the file needs.
struct ReaderView: View {
    let item: LibraryItemSummary

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingSettings = false
    @State private var isShowingHighlights = false
    @State private var isShowingChrome = true
    @State private var chromeTimer: Task<Void, Never>?
    @State private var selectedText: String?

    private var reader: ReaderController { environment.reader }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            content
            if isShowingChrome { chrome }
        }
        .statusBarHidden(!isShowingChrome)
        .task {
            await reader.open(item: item)
            // The bars introduce themselves, then leave. Reading is the point
            // of this screen; a tap anywhere brings them back.
            scheduleChromeHide()
        }
        .onDisappear {
            chromeTimer?.cancel()
            Task { await reader.close() }
        }
        .sheet(isPresented: $isShowingSettings) { ReaderSettingsSheet() }
        .sheet(isPresented: $isShowingHighlights) { HighlightsSheet() }
        .sheet(item: Binding(
            get: { selectedText.map { SelectedPassage(text: $0) } },
            set: { if $0 == nil { selectedText = nil } }
        )) { passage in
            AddHighlightSheet(text: passage.text) { color, note in
                Task { await reader.addHighlight(text: passage.text, color: color, note: note) }
            }
        }
    }

    private var background: Color {
        guard let colors = reader.settings.theme.colors else { return Palette.background }
        return Color(.sRGB, red: colors.background.r, green: colors.background.g, blue: colors.background.b)
    }

    @ViewBuilder
    private var content: some View {
        switch reader.content {
        case .none:
            if reader.isOpening {
                LoadingStateView(title: Text(L("Opening…")))
            } else if let failure = reader.failure {
                ErrorStateView(message: Text(verbatim: failure)) {
                    Task { await reader.open(item: item) }
                }
            } else {
                EmptyStateView(
                    systemImage: "book",
                    title: Text(L("Nothing to read")),
                    message: Text(L("This item has no ebook file."))
                )
            }

        case .epub(let publication):
            EPUBReaderView(
                publication: publication,
                initialLocator: nil,
                settings: reader.settings,
                onLocatorChange: { reader.locationChanged(locator: $0) },
                onSelection: { text, _ in selectedText = text }
            )
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture { toggleChrome() }

        case .pdf(let url):
            PDFReaderView(
                url: url,
                settings: reader.settings,
                currentPage: Binding(
                    get: { reader.currentPage },
                    set: { reader.pageChanged(to: $0) }
                ),
                pageCount: Binding(
                    get: { reader.pageCount },
                    set: { reader.pageCount = $0 }
                ),
                onSelection: { selectedText = $0 }
            )
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture { toggleChrome() }

        case .converting(let progress):
            VStack(spacing: Spacing.m) {
                ProgressView(value: Self.fraction(of: progress))
                    .tint(Palette.accent)
                    .frame(maxWidth: 220)
                Text(verbatim: Self.label(for: progress))
                    .font(Typography.body)
                    .foregroundStyle(Palette.secondaryText)
                Text(L("Kindle books are converted once, then open instantly."))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.xl)
            .accessibilityElement(children: .combine)

        case .comic(let url):
            ComicPagerView(item: item, fileURL: url)

        case .unsupported(let format):
            EmptyStateView(
                systemImage: "doc.questionmark",
                title: Text(L("Can't open \(format) yet")),
                message: Text(L("CBR needs a RAR decoder that isn't bundled yet. Kindle formats arrive in a later version."))
            )
        }
    }

    // MARK: - Chrome

    @MainActor
    private func toggleChrome() {
        if isShowingChrome {
            chromeTimer?.cancel()
            withAnimation(Motion.quick) { isShowingChrome = false }
        } else {
            withAnimation(Motion.quick) { isShowingChrome = true }
            scheduleChromeHide()
        }
    }

    /// Hides the bars again after a moment, unless something the user opened
    /// from them is still on screen.
    @MainActor
    private func scheduleChromeHide() {
        chromeTimer?.cancel()
        chromeTimer = Task {
            try? await Task.sleep(for: Motion.chromeLinger)
            guard !Task.isCancelled else { return }
            guard !isShowingSettings, !isShowingHighlights, selectedText == nil else { return }
            withAnimation(Motion.quick) { isShowingChrome = false }
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

                Text(verbatim: reader.chapterTitle ?? reader.title)
                    .font(Typography.caption)
                    .lineLimit(1)

                Spacer()

                Button { isShowingHighlights = true } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel(L("Highlights"))

                Button { isShowingSettings = true } label: {
                    Image(systemName: "textformat.size")
                }
                .accessibilityLabel(L("Reading settings"))
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .firelightGlass(in: Capsule())
            .padding(.horizontal, Spacing.m)

            Spacer()

            footer
        }
        .transition(.opacity)
    }

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            ProgressView(value: reader.progression)
                .tint(Palette.accent)

            HStack {
                Text(verbatim: "\(Int(reader.progression * 100))%")
                Spacer()
                if let remaining = reader.timeRemaining {
                    Text(verbatim: L("\(Format.duration(remaining)) left"))
                } else {
                    // Honest: a figure needs evidence, and there isn't any yet.
                    Text(L("Time left appears as you read"))
                }
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.secondaryText)
        }
        .padding(Spacing.m)
        .firelightGlass(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .padding(.horizontal, Spacing.m)
        .padding(.bottom, Spacing.s)
    }
}

extension ReaderView {
    static func fraction(of progress: ConversionProgress) -> Double {
        switch progress {
        case .parsing: 0.1
        case .writing(let fraction): 0.1 + fraction * 0.8
        case .validating: 0.95
        case .finished: 1
        }
    }

    static func label(for progress: ConversionProgress) -> String {
        switch progress {
        case .parsing: L("Reading the book…")
        case .writing: L("Converting to EPUB…")
        case .validating: L("Checking the result…")
        case .finished: L("Done")
        }
    }
}

struct SelectedPassage: Identifiable {
    let id = UUID()
    let text: String
}
