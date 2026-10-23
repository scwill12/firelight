import ABSKit
import DesignSystem
import SwiftUI

/// Connecting a Hardcover account.
///
/// Off unless the user turns it on, and the token never leaves the Keychain.
struct HardcoverSettingsView: View {
    @State private var token = ""
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, checking
        case connected(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Section {
                SecureField(L("API token"), text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await connect() }
                } label: {
                    if status == .checking {
                        HStack(spacing: Spacing.s) { ProgressView(); Text(L("Checking…")) }
                    } else {
                        Text(L("Connect"))
                    }
                }
                .disabled(token.isEmpty || status == .checking)

                if case .connected(let username) = status {
                    Label(L("Connected as \(username)"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.accent)
                }
                if case .failed(let message) = status {
                    Text(verbatim: message).foregroundStyle(Palette.destructive)
                }
            } header: {
                Text(L("Hardcover"))
            } footer: {
                Text(L("Firelight marks books as reading and finished on your Hardcover shelf. The token is stored in your Keychain and sent only to Hardcover. Tokens expire after a year."))
            }

            if case .connected = status {
                Section {
                    Button(role: .destructive) {
                        try? HardcoverClient.store(token: nil)
                        token = ""
                        status = .idle
                    } label: {
                        Text(L("Disconnect"))
                    }
                }
            }
        }
        .navigationTitle(Text(L("Hardcover")))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let stored = HardcoverClient.storedToken() {
                token = stored
                status = .connected(L("your account"))
            }
        }
    }

    private func connect() async {
        status = .checking
        let client = HardcoverClient(token: token)
        do {
            let user = try await client.currentUser()
            try HardcoverClient.store(token: token)
            status = .connected(user.username.isEmpty ? L("your account") : user.username)
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? L("That didn't work."))
        }
    }
}
