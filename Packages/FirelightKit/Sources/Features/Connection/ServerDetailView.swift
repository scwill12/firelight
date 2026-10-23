import ABSKit
import DesignSystem
import SwiftUI

/// One server's addresses, headers and version.
struct ServerDetailView: View {
    let server: ServerDescriptor

    @Environment(AppEnvironment.self) private var environment
    @State private var remoteText = ""
    @State private var localText = ""
    @State private var headers: [HeaderPair] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            Section {
                TextField(L("Remote address"), text: $remoteText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(L("Local address (optional)"), text: $localText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(L("Addresses"))
            } footer: {
                Text(L("Both are tried at once. The local one wins whenever it answers."))
            }

            Section {
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
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        HStack(spacing: Spacing.s) { ProgressView(); Text(L("Saving…")) }
                    } else {
                        Text(L("Save and reconnect"))
                    }
                }
                .disabled(isSaving || remoteText.isEmpty)
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingRemoval = true
                } label: {
                    Text(L("Remove this server"))
                }
            } footer: {
                Text(L("Removes the server, its accounts and its saved credentials from this device. Nothing on the server changes."))
            }
        }
        .navigationTitle(Text(verbatim: server.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            remoteText = server.remoteURL.absoluteString
            localText = server.localURL?.absoluteString ?? ""
            headers = Array(dictionary: environment.session.customHeaders(for: server.id))
        }
        .alert(L("Couldn't save"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L("OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(L("Remove \(server.displayName)?"),
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(L("Remove"), role: .destructive) {
                Task { await environment.session.removeServer(id: server.id) }
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try environment.session.saveCustomHeaders(headers.asDictionary, for: server.id)
            try await environment.session.updateAddresses(
                serverID: server.id,
                localURLText: localText,
                remoteURLText: remoteText
            )
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't save those addresses."
        }
    }
}
