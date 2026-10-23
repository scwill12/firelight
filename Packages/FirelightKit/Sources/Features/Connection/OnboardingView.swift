import ABSKit
import DesignSystem
import SwiftUI

/// Adding the first server, and every one after it.
///
/// The address is checked live, because the most common failure in a
/// self-hosted app is an address that was never going to work, and finding out
/// after typing a password is a bad way to learn it.
public struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var addressText = ServerURLParser.defaultScheme
    // Not prefilled: this field's placeholder is its only label, and a
    // prefilled one would read as an address the user had asked for.
    @State private var localAddressText = ""
    @State private var displayName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var headers: [HeaderPair] = []

    @State private var check: ConnectionCheckResult?
    @State private var checkTask: Task<Void, Never>?
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    /// Set when this is the first server; the sheet can't be dismissed then.
    private let isFirstServer: Bool

    public init(isFirstServer: Bool = true) {
        self.isFirstServer = isFirstServer
    }

    public var body: some View {
        NavigationStack {
            Form {
                addressSection
                if check?.isReachable == true {
                    signInSection
                }
                advancedSection
            }
            .navigationTitle(isFirstServer ? Text(L("Add your server")) : Text(L("Add a server")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstServer {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L("Cancel")) { dismiss() }
                    }
                }
            }
            .alert(L("Couldn't sign in"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(L("OK"), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Palette.accent)
    }

    // MARK: - Address

    private var addressSection: some View {
        Section {
            TextField(L("books.example.com"), text: $addressText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: addressText) { scheduleCheck() }
                .onSubmit { scheduleCheck(immediately: true) }

            if let check {
                checkRow(check)
            }
        } header: {
            Text(L("Server address"))
        } footer: {
            Text(L("Your own Audiobookshelf server. Firelight never talks to anything else."))
        }
    }

    @ViewBuilder
    private func checkRow(_ result: ConnectionCheckResult) -> some View {
        switch result {
        case .checking:
            HStack(spacing: Spacing.s) {
                ProgressView()
                Text(L("Checking…")).foregroundStyle(Palette.secondaryText)
            }
        case .reachable(let version, let methods, _):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label {
                    Text("Audiobookshelf \(version ?? "")")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                }
                if methods.contains("openid") {
                    Text(L("Single sign-on is available."))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
                if let version, let parsed = ServerVersion(version), parsed < ServerVersion(major: 2, minor: 26, patch: 0) {
                    Text(L("This server is older than 2.26, so Firelight will use the legacy sign-in and may need you to sign in again more often."))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.notice)
                }
            }
            .accessibilityElement(children: .combine)
        case .untrustedCertificate(let fingerprint, let host):
            certificateRow(fingerprint: fingerprint, host: host)
        case .notAudiobookshelf:
            Label {
                Text(L("Something answered, but it isn't Audiobookshelf."))
            } icon: {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(Palette.notice)
            }
        case .unreachable:
            Label {
                Text(L("Can't reach that address."))
            } icon: {
                Image(systemName: "wifi.slash").foregroundStyle(Palette.notice)
            }
        case .failed(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.destructive)
            }
        }
    }

    /// Trusting a self-signed certificate is a real decision, so the user is
    /// shown exactly what they are trusting before they do it.
    private func certificateRow(fingerprint: String?, host: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(L("This server's certificate isn't trusted"))
            } icon: {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .foregroundStyle(Palette.notice)
            }
            if let fingerprint {
                Text(L("SHA-256"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                Text(verbatim: fingerprint)
                    .font(Typography.timecode)
                    .textSelection(.enabled)
                Text(L("Check this matches your server before trusting it."))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
                Button(L("Trust this certificate")) {
                    Task {
                        await environment.session.factory.trust.trustRejected(forHost: host)
                        scheduleCheck(immediately: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            } else {
                Text(L("Firelight couldn't read the certificate to show you its fingerprint."))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }

    // MARK: - Sign in

    private var signInSection: some View {
        Section {
            TextField(L("Username"), text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(L("Password"), text: $password)
                .textContentType(.password)

            Button {
                Task { await signIn() }
            } label: {
                if isSigningIn {
                    HStack(spacing: Spacing.s) {
                        ProgressView()
                        Text(L("Signing in…"))
                    }
                } else {
                    Text(L("Sign In"))
                }
            }
            .disabled(username.isEmpty || password.isEmpty || isSigningIn)

            if check?.supportsOpenID == true {
                Button {
                    Task { await signInWithOpenID() }
                } label: {
                    Label(L("Sign in with single sign-on"), systemImage: "person.badge.key")
                }
                .disabled(isSigningIn)
            }
        } header: {
            Text(L("Account"))
        } footer: {
            if check?.supportsOpenID == true {
                Text(L("Single sign-on needs \(OIDCSignInService.redirectURI) in your server's mobile redirect URIs."))
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            TextField(L("Name (optional)"), text: $displayName)
            TextField(L("Local address (optional)"), text: $localAddressText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            NavigationLink {
                CustomHeadersView(headers: $headers)
            } label: {
                LabeledContent {
                    Text(headers.isEmpty ? "None" : "\(headers.count)")
                        .foregroundStyle(Palette.secondaryText)
                } label: {
                    Text(L("Custom headers"))
                }
            }
        } header: {
            Text(L("Advanced"))
        } footer: {
            Text(L("A local address is used automatically whenever it answers, so you're not going out to the internet at home."))
        }
    }

    // MARK: - Actions

    /// The local address only when the user actually typed one.
    private var enteredLocalAddress: String? {
        ServerURLParser.isBlank(localAddressText) ? nil : localAddressText
    }

    private func scheduleCheck(immediately: Bool = false) {
        checkTask?.cancel()
        let text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ServerURLParser.isBlank(text) else {
            check = nil
            return
        }
        let draftHeaders = headers.asDictionary
        checkTask = Task {
            if !immediately {
                // Don't probe on every keystroke.
                try? await Task.sleep(for: .milliseconds(600))
                if Task.isCancelled { return }
            }
            check = .checking
            let result = await ConnectionChecker(factory: environment.session.factory)
                .check(urlText: text, headers: draftHeaders)
            if !Task.isCancelled { check = result }
        }
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            _ = try await environment.session.addServer(
                displayName: displayName,
                remoteURLText: addressText,
                localURLText: enteredLocalAddress,
                username: username,
                password: password,
                customHeaders: headers.asDictionary
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Sign-in didn't complete."
        }
    }

    private func signInWithOpenID() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            _ = try await environment.session.addServerWithOpenID(
                displayName: displayName,
                remoteURLText: addressText,
                localURLText: enteredLocalAddress,
                customHeaders: headers.asDictionary
            )
            dismiss()
        } catch SessionError.cancelled {
            // The user closed the browser sheet; that isn't an error.
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Single sign-on didn't complete."
        }
    }
}
