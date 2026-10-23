import DesignSystem
import MessageUI
import Persistence
import ReaderKit
import SwiftUI

/// Getting a book out of Firelight: to another app, or to a Kindle.
struct ExportSheet: View {
    let item: LibraryItemSummary

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var fileURL: URL?
    @State private var fileSize: Int64 = 0
    @State private var isPreparing = true
    @State private var failure: String?
    @State private var isShowingShareSheet = false
    @State private var isShowingMail = false
    @State private var isShowingSenderNotice = false
    @AppStorage("firelight.kindleAddress") private var kindleAddress = ""
    @AppStorage("firelight.kindleNoticeSeen") private var hasSeenSenderNotice = false

    private var format: EbookFormat? {
        item.ebookFormat.flatMap(EbookFormatDetector.format(forFileExtension:))
    }

    private var refusal: KindleDelivery.Refusal? {
        KindleDelivery.check(
            format: format,
            fileSizeBytes: fileSize,
            kindleAddress: kindleAddress,
            canSendMail: MFMailComposeViewController.canSendMail()
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if isPreparing {
                    LoadingStateView(title: Text(L("Preparing the file…")))
                } else if let failure {
                    ErrorStateView(message: Text(verbatim: failure)) {
                        Task { await prepare() }
                    }
                } else {
                    options
                }
            }
            .navigationTitle(Text(L("Export")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { dismiss() } }
            }
            .task { await prepare() }
            .sheet(isPresented: $isShowingShareSheet) {
                if let fileURL { ShareSheet(items: [fileURL]) }
            }
            .sheet(isPresented: $isShowingMail) {
                if let fileURL {
                    MailComposeView(
                        recipient: kindleAddress,
                        subject: KindleDelivery.subject(forBookTitle: item.title),
                        attachment: fileURL,
                        mimeType: format == .pdf ? "application/pdf" : "application/epub+zip"
                    ) { _ in
                        isShowingMail = false
                    }
                }
            }
            .alert(L("Before you send"), isPresented: $isShowingSenderNotice) {
                Button(L("Got it")) {
                    hasSeenSenderNotice = true
                    isShowingMail = true
                }
                Button(L("Cancel"), role: .cancel) {}
            } message: {
                Text(verbatim: KindleDelivery.approvedSenderNotice)
            }
        }
    }

    private var options: some View {
        List {
            Section {
                LabeledContent {
                    Text(verbatim: StorageFormatterShim.string(fromBytes: fileSize))
                        .foregroundStyle(Palette.secondaryText)
                } label: {
                    Text(verbatim: format?.displayName ?? L("File"))
                }
            } header: {
                Text(verbatim: item.title)
            }

            Section {
                Button {
                    isShowingShareSheet = true
                } label: {
                    Label(L("Share the original file"), systemImage: "square.and.arrow.up")
                }
                .disabled(fileURL == nil)
            } footer: {
                Text(L("Opens the share sheet, so you can send it anywhere or save it to Files."))
            }

            Section {
                Button {
                    if hasSeenSenderNotice {
                        isShowingMail = true
                    } else {
                        isShowingSenderNotice = true
                    }
                } label: {
                    Label(L("Send to Kindle"), systemImage: "envelope")
                }
                .disabled(refusal != nil)

                if let refusal {
                    Text(verbatim: refusal.message)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.notice)
                }

                TextField(L("Kindle email address"), text: $kindleAddress)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(L("Kindle"))
            } footer: {
                Text(L("Saved on this device only. Firelight never sends it anywhere but your own mail app."))
            }
        }
    }

    private func prepare() async {
        isPreparing = true
        failure = nil
        defer { isPreparing = false }

        guard let client = environment.session.client(), let format else {
            failure = L("This item has no ebook file.")
            return
        }
        do {
            let destination = try ReaderController.cacheURL(itemID: item.id, format: format)
            let url: URL
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                url = destination
            } else {
                url = try await client.downloadEbook(itemID: item.id, to: destination)
            }
            fileURL = url
            fileSize = (try? FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false)
            )[.size] as? Int64) ?? 0
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? L("Couldn't fetch the file.")
        }
    }
}

/// Keeps `DownloadKit`'s formatter available here without importing it for one
/// function.
enum StorageFormatterShim {
    static func string(fromBytes bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

/// The system mail composer, pre-filled.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let attachment: URL
    let mimeType: String
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        // Amazon reads the attachment and ignores the body.
        if let data = try? Data(contentsOf: attachment) {
            controller.addAttachmentData(
                data,
                mimeType: mimeType,
                fileName: attachment.lastPathComponent
            )
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            onFinish(result == .sent)
        }
    }
}
