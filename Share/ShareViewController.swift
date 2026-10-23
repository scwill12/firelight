import ABSKit
import DesignSystem
import Persistence
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Add to Audiobookshelf".
///
/// The extension builds its own client from the shared container and the
/// shared Keychain — it never opens the database, because a share sheet has to
/// appear immediately.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let root = ShareRootView(
            provider: SharedFileProvider(extensionContext: extensionContext),
            onDone: { [weak self] in self?.finish() }
        )

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [])
    }
}

/// Pulls the shared files out of the extension context.
struct SharedFileProvider {
    let items: [NSItemProvider]

    init(extensionContext: NSExtensionContext?) {
        items = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
    }

    /// Loads each attachment into memory.
    ///
    /// A share sheet hands over files the user picked deliberately, so this is
    /// bounded by what they chose — but an audiobook can be large, and the
    /// extension's memory limit is far smaller than the app's.
    ///
    /// Main-actor isolated because `NSItemProvider` is not `Sendable` and the
    /// extension context handed these to us there.
    @MainActor
    func load() async -> [UploadFile] {
        var files: [UploadFile] = []
        for provider in items {
            guard let url = try? await provider.loadFileURL() else { continue }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            let name = url.lastPathComponent
            files.append(UploadFile(
                filename: name,
                mimeType: UploadFile.mimeType(forFilename: name),
                data: data
            ))
        }
        return files
    }
}

extension NSItemProvider {
    /// Main-actor isolated so awaiting it does not send a non-Sendable
    /// `NSItemProvider` across isolation domains.
    @MainActor
    func loadFileURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadFileRepresentation(for: .item, openInPlace: false) { url, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    // The URL is only valid inside this callback, so copy now.
                    let copy = FileManager.default.temporaryDirectory
                        .appending(path: url.lastPathComponent)
                    try? FileManager.default.removeItem(at: copy)
                    try? FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

struct ShareRootView: View {
    let provider: SharedFileProvider
    let onDone: () -> Void

    @State private var libraries: [ABSLibraryWithFolders] = []
    @State private var selectedLibraryID: String?
    @State private var selectedFolderID: String?
    @State private var title = ""
    @State private var author = ""
    @State private var series = ""
    @State private var files: [UploadFile] = []
    @State private var phase: Phase = .loading
    @State private var failure: String?

    /// Named apart from `State` so it does not shadow the property wrapper.
    enum Phase { case loading, notConfigured, ready, uploading, done }

    private var selectedLibrary: ABSLibraryWithFolders? {
        libraries.first { $0.id == selectedLibraryID }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    ProgressView(L("Looking for your server…"))
                case .notConfigured:
                    notConfigured
                case .ready, .uploading:
                    form
                case .done:
                    finished
                }
            }
            .navigationTitle(Text(L("Add to Audiobookshelf")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Cancel"), action: onDone)
                }
                if phase == .ready {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("Upload")) { Task { await upload() } }
                            .disabled(!canUpload)
                    }
                }
            }
            .task { await load() }
        }
        .tint(Palette.accent)
    }

    private var canUpload: Bool {
        selectedLibraryID != nil && selectedFolderID != nil
        && !title.trimmingCharacters(in: .whitespaces).isEmpty
        && !files.isEmpty
    }

    private var notConfigured: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accent)
            Text(L("No server yet"))
                .font(Typography.sectionTitle)
            Text(L("Add your Audiobookshelf server in Firelight, then come back here."))
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    private var finished: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accent)
            Text(L("Uploaded"))
                .font(Typography.sectionTitle)
            Text(L("Audiobookshelf will pick it up on its next scan."))
                .font(Typography.body)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            Button(L("Done"), action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
        }
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
    }

    private var form: some View {
        Form {
            Section {
                ForEach(files, id: \.filename) { file in
                    LabeledContent {
                        Text(verbatim: ByteCountFormatter().string(fromByteCount: Int64(file.data.count)))
                            .foregroundStyle(Palette.secondaryText)
                    } label: {
                        Text(verbatim: file.filename).lineLimit(1).truncationMode(.middle)
                    }
                }
                if files.isEmpty {
                    Text(L("Nothing to upload.")).foregroundStyle(Palette.secondaryText)
                }
            } header: {
                Text(L("Files"))
            }

            Section {
                Picker(L("Library"), selection: $selectedLibraryID) {
                    ForEach(libraries) { library in
                        Text(verbatim: library.name).tag(Optional(library.id))
                    }
                }
                if let folders = selectedLibrary?.folders, folders.count > 1 {
                    Picker(L("Folder"), selection: $selectedFolderID) {
                        ForEach(folders) { folder in
                            Text(verbatim: folder.fullPath ?? folder.id).tag(Optional(folder.id))
                        }
                    }
                }
            } header: {
                Text(L("Destination"))
            }

            Section {
                TextField(L("Title"), text: $title)
                if selectedLibrary?.isPodcast != true {
                    TextField(L("Author (optional)"), text: $author)
                    TextField(L("Series (optional)"), text: $series)
                }
            } header: {
                Text(L("Details"))
            } footer: {
                Text(L("The server builds the folder path from these, so they decide where the file lands."))
            }

            if phase == .uploading {
                Section {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text(L("Uploading…"))
                    }
                }
            }

            if let failure {
                Section {
                    Text(verbatim: failure).foregroundStyle(Palette.destructive)
                }
            }
        }
        .onChange(of: selectedLibraryID) { _, _ in
            selectedFolderID = selectedLibrary?.folders?.first?.id
        }
    }

    // MARK: - Work

    private func load() async {
        files = await provider.load()
        if title.isEmpty, let first = files.first {
            title = (first.filename as NSString).deletingPathExtension
        }

        guard let client = Self.makeClient() else {
            phase = .notConfigured
            return
        }
        do {
            libraries = try await client.librariesWithFolders()
            selectedLibraryID = libraries.first?.id
            selectedFolderID = libraries.first?.folders?.first?.id
            phase = .ready
        } catch {
            failure = L("Couldn't reach your server.")
            phase = .ready
        }
    }

    private func upload() async {
        guard let client = Self.makeClient(),
              let libraryID = selectedLibraryID,
              let folderID = selectedFolderID
        else { return }

        phase = .uploading
        failure = nil
        do {
            try await client.upload(UploadRequest(
                libraryID: libraryID,
                folderID: folderID,
                title: title.trimmingCharacters(in: .whitespaces),
                author: author.isEmpty ? nil : author,
                series: series.isEmpty ? nil : series,
                files: files
            ))
            phase = .done
        } catch APIError.forbidden {
            failure = L("Your account doesn't have permission to upload.")
            phase = .ready
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? L("The upload didn't finish.")
            phase = .ready
        }
    }

    /// Builds a client from the shared container and the shared Keychain.
    private static func makeClient() -> ABSClient? {
        guard let server = SharedState.activeServer else { return nil }
        let keychain = KeychainStore()
        let token = try? keychain.string(for: KeychainKey.accessToken(serverID: server.id))
        let headers = (try? keychain.value(
            [String: String].self, for: KeychainKey.customHeaders(serverID: server.id)
        )) ?? [:]

        return ABSClient(http: URLSessionHTTPClient(
            baseURL: server.baseURL,
            tokens: StaticToken(token: token ?? nil),
            customHeaders: StaticCustomHeaders(headers ?? [:])
        ))
    }
}

/// The extension cannot refresh a token — it has no way to persist a new one
/// safely while the app may also be running — so it uses what is there and
/// reports a clear failure if it has expired.
private struct StaticToken: AccessTokenProviding {
    let token: String?
    func accessToken() async -> String? { token }
    func refreshAccessToken() async throws -> String? { nil }
}
