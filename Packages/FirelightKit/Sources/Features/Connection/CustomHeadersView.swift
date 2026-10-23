import DesignSystem
import SwiftUI

/// Name/value pairs sent with every request to one server.
///
/// For Cloudflare Access, Authelia, Authentik and anything else that gates a
/// self-hosted server behind a proxy. Values are secrets, so they are masked
/// and stored in the Keychain, never in the database.
struct CustomHeadersView: View {
    @Binding var headers: [HeaderPair]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach($headers) { $pair in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField(L("Header name"), text: $pair.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Typography.emphasisedBody)
                        SecureField(L("Value"), text: $pair.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(Typography.body)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .padding(.vertical, Spacing.hair)
                }
                .onDelete { headers.remove(atOffsets: $0) }

                Button {
                    headers.append(HeaderPair())
                } label: {
                    Label(L("Add header"), systemImage: "plus.circle")
                }
            } header: {
                Text(L("Custom headers"))
            } footer: {
                Text(L("Sent with every request to this server. Use these if it sits behind Cloudflare Access, Authelia or a similar proxy. Values are kept in the Keychain."))
            }

            if headers.isEmpty {
                Section {
                    Text(L("No custom headers. Most servers don't need any."))
                        .font(Typography.body)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .navigationTitle(L("Custom headers"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Done")) { dismiss() }
            }
        }
    }
}

/// One editable header row. Identified so SwiftUI can track rows as they are
/// added and removed while being typed into.
struct HeaderPair: Identifiable, Hashable {
    let id = UUID()
    var name: String = ""
    var value: String = ""

    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

extension Array where Element == HeaderPair {
    var asDictionary: [String: String] {
        reduce(into: [:]) { result, pair in
            guard pair.isUsable else { return }
            result[pair.name.trimmingCharacters(in: .whitespaces)] = pair.value
        }
    }

    init(dictionary: [String: String]) {
        self = dictionary
            .sorted { $0.key < $1.key }
            .map { HeaderPair(name: $0.key, value: $0.value) }
    }
}
