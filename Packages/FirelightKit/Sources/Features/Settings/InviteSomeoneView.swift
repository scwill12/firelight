import ABSKit
import DesignSystem
import SwiftUI

/// Creates an account on this server and hands back the code that unlocks it.
///
/// The admin never chooses or sees a password: one is generated, travels in
/// the code, and is replaced by whatever the invited person picks. That is
/// deliberate — an admin who knows the password is an admin who can be asked
/// for it later.
struct InviteSomeoneView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var serverAddress = ""
    @State private var expiry: Expiry = .week
    @State private var code: String?
    @State private var isCreating = false
    @State private var failure: String?
    @State private var isShowingShare = false
    @FocusState private var isNaming: Bool

    /// Short options only. An invitation that lives for a month is a password
    /// sitting in somebody's messages for a month.
    private enum Expiry: String, CaseIterable, Identifiable {
        case day, threeDays, week

        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .day: 24 * 60 * 60
            case .threeDays: 3 * 24 * 60 * 60
            case .week: 7 * 24 * 60 * 60
            }
        }
        var label: String {
            switch self {
            case .day: L("A day")
            case .threeDays: L("Three days")
            case .week: L("A week")
            }
        }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The address the invitation will carry, which is not necessarily the
    /// one this device is talking to.
    private var invitedURL: URL? {
        ServerURLParser.parse(serverAddress)
    }

    private var canCreate: Bool {
        !trimmedUsername.isEmpty && invitedURL != nil && !isCreating
    }

    /// Headers this device sends that an invitation cannot carry.
    ///
    /// A server behind Cloudflare Access, or anything else that wants a token
    /// before Audiobookshelf is reached, is configured here as custom headers.
    /// They are deliberately **not** put in the code: they are a shared secret
    /// that redeeming an invitation would not spend, so a code carrying them
    /// would stay dangerous forever. The admin needs to know, though —
    /// otherwise the invited person meets a login wall that has nothing to do
    /// with Firelight.
    private var customHeaderNames: [String] {
        guard let server = environment.session.activeServer else { return [] }
        return environment.session.customHeaders(for: server.id).keys.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                if let code {
                    madeSection(code)
                } else {
                    makeSection
                }
            }
            .navigationTitle(Text(L("Invite someone")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(code == nil ? L("Cancel") : L("Done")) { dismiss() }
                }
            }
            .alert(
                L("Couldn't invite"),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button(L("OK"), role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .sheet(isPresented: $isShowingShare) {
                if let code { ShareSheet(items: [code]) }
            }
            .onAppear {
                isNaming = true
                // The *remote* address, not the one this device resolved to.
                // At home that is usually the LAN address, and an invitation
                // carrying it reaches nobody outside the house.
                if serverAddress.isEmpty {
                    serverAddress = environment.session.activeServer?
                        .remoteURL.absoluteString ?? ""
                }
            }
        }
        .tint(Palette.accent)
    }

    // MARK: - Before

    private var makeSection: some View {
        Group {
            Section {
                TextField(L("Username"), text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isNaming)
                    .submitLabel(.go)
                    .onSubmit { if !trimmedUsername.isEmpty { Task { await create() } } }
            } header: {
                Text(L("New account"))
            } footer: {
                Text(L("They'll sign in with this name and choose their own password when they accept."))
            }

            Section {
                TextField(L("Server address"), text: $serverAddress)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(L("Address they'll use"))
            } footer: {
                if serverAddress.isEmpty || invitedURL != nil {
                    Text(L("Your server's address from outside your home. Firelight has filled in the remote one it knows — if you're inviting someone who isn't on your network, a home address like 192.168.1.10 won't reach you."))
                } else {
                    Text(L("That doesn't look like a server address."))
                        .foregroundStyle(Palette.notice)
                }
            }

            if !customHeaderNames.isEmpty {
                Section {
                    Label {
                        Text(L("This server needs headers that an invitation can't carry: \(customHeaderNames.joined(separator: ", "))."))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.notice)
                    }
                    .font(Typography.caption)
                } footer: {
                    Text(L("They're a shared secret, and accepting an invitation wouldn't retire them. Give the person access the same way you gave yourself — in Cloudflare Access or whatever sits in front — rather than sending them your token."))
                }
            }

            Section {
                Picker(selection: $expiry) {
                    ForEach(Expiry.allCases) { option in
                        Text(verbatim: option.label).tag(option)
                    }
                } label: {
                    Text(L("Expires after"))
                }
            } footer: {
                Text(L("Until it's accepted, the code works for anyone who has it. Firelight stops offering it after this, though the account stays."))
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        HStack(spacing: Spacing.s) {
                            ProgressView()
                            Text(L("Creating…"))
                        }
                    } else {
                        Text(L("Create the account"))
                    }
                }
                .disabled(!canCreate)
            } footer: {
                Text(L("The account can download and read. It can't delete, upload or change anything on your server."))
            }
        }
    }

    // MARK: - After

    private func madeSection(_ code: String) -> some View {
        Group {
            Section {
                Text(verbatim: code)
                    .font(Typography.timecode)
                    .textSelection(.enabled)
                    .padding(.vertical, Spacing.xs)
            } header: {
                Text(L("Send this to \(trimmedUsername)"))
            } footer: {
                Text(L("Send it the way you'd send a password — directly, to them. Anyone who reads it before they do can take the account."))
            }

            Section {
                Button {
                    isShowingShare = true
                } label: {
                    Label(L("Share"), systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = code
                    Haptics.success()
                } label: {
                    Label(L("Copy"), systemImage: "doc.on.doc")
                }
            } footer: {
                Text(L("They'll need Firelight, then: I have an invitation."))
            }
        }
    }

    // MARK: - Actions

    private func create() async {
        isCreating = true
        defer { isCreating = false }

        guard let client = environment.session.client() else {
            failure = L("Not connected to a server.")
            return
        }
        guard let baseURL = invitedURL else {
            failure = L("That doesn't look like a server address.")
            return
        }

        let password = TemporaryPassword.make()
        do {
            _ = try await client.createUser(username: trimmedUsername, password: password)
        } catch {
            failure = (error as? LocalizedError)?.errorDescription
                ?? L("The account couldn't be created. That name may already be taken.")
            return
        }

        do {
            code = try InviteCode.make(from: Invite(
                serverURL: baseURL,
                username: trimmedUsername,
                temporaryPassword: password,
                expiresAt: Date.now.addingTimeInterval(expiry.seconds)
            ))
            Haptics.success()
        } catch {
            // The account exists; only the code failed. Say so, because the
            // admin now has a user on their server they did not plan for.
            failure = L("The account was created, but the code couldn't be made. Remove \(trimmedUsername) on your server and try again.")
        }
    }
}
