import PDFKit
import SwiftUI

/// Reads a PDF.
///
/// PDFKit rather than Readium: a PDF is a fixed layout, so the typography
/// settings that matter for an EPUB do not apply, and PDFKit's rendering and
/// text selection are better than anything worth rebuilding.
public struct PDFReaderView: UIViewRepresentable {
    private let url: URL
    private let settings: ReaderSettings
    @Binding private var currentPage: Int
    @Binding private var pageCount: Int
    private let onSelection: (String) -> Void

    public init(
        url: URL,
        settings: ReaderSettings,
        currentPage: Binding<Int>,
        pageCount: Binding<Int>,
        onSelection: @escaping (String) -> Void = { _ in }
    ) {
        self.url = url
        self.settings = settings
        self._currentPage = currentPage
        self._pageCount = pageCount
        self.onSelection = onSelection
    }

    public func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = false
        view.delegate = context.coordinator

        if let document = PDFDocument(url: url) {
            view.document = document
            DispatchQueue.main.async {
                pageCount = document.pageCount
                if currentPage > 1, let page = document.page(at: currentPage - 1) {
                    view.go(to: page)
                }
            }
        }

        apply(settings, to: view)

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: view
        )
        return view
    }

    public func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChange = { page in
            if currentPage != page { currentPage = page }
        }
        context.coordinator.onSelection = onSelection
        apply(settings, to: view)

        // Follow a programmatic jump, such as tapping a highlight.
        if let document = view.document,
           currentPage >= 1, currentPage <= document.pageCount,
           let target = document.page(at: currentPage - 1),
           view.currentPage != target {
            view.go(to: target)
        }
    }

    private func apply(_ settings: ReaderSettings, to view: PDFView) {
        view.displayDirection = settings.pageTurn == .scroll ? .vertical : .horizontal
        view.usePageViewController(settings.pageTurn != .scroll, withViewOptions: nil)
        // Two pages side by side when the page is wide enough and the reader
        // asked for it.
        let isWide = view.bounds.width > view.bounds.height && view.bounds.width > 700
        view.displayMode = (settings.allowsTwoColumns && isWide) ? .twoUpContinuous : .singlePageContinuous

        if let colors = settings.theme.colors {
            view.backgroundColor = UIColor(
                red: colors.background.r,
                green: colors.background.g,
                blue: colors.background.b,
                alpha: 1
            )
        } else {
            view.backgroundColor = .systemBackground
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator: NSObject, PDFViewDelegate {
        var onPageChange: ((Int) -> Void)?
        var onSelection: ((String) -> Void)?

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let document = view.document
            else { return }
            onPageChange?(document.index(for: page) + 1)
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let text = view.currentSelection?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            onSelection?(text)
        }
    }
}
