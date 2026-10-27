import ABSKit
import DesignSystem
import SwiftUI

/// What someone sees after pasting an invitation code.
///
/// Deliberately not a sign-in form. The person being invited never had a
/// password — one was made for them, travelled in the code, and is about to
/// be thrown away. Asking them to "sign in" would be asking for something
/// they do not have; asking them to choose a password is the truth.
struct InvitationView: View {
    let invite: Invite

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isAccepting = false
    @State private var failure: String?
    @FocusState private var focus: Field?

    private enum Field { case password, confirmation }

    /// Short, because this is a password for a private audiobook server, not
    /// a bank. A rule nobody can satisfy gets written on a sticky note.
    private static let minimumLength = 8

    private var serverName: String {
        invite.serverURL.host() ?? invite.serverURL.absoluteString
    }

    private var problem: String? {
        if password.isEmpty { return nil }
        if password.count < Self.minimumLength {
            return L("At least \(Self.minimumLength) characters.")
        }
        if !confirmation.isEmpty, password != confirmation {
            return L("These don't match.")
        }
        return nil
    }

    private var canAccept: Bool {
        password.count >= Self.minimumLength && password == confirmation && !isAccepting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text(verbatim: L("Hello, \(invite.username)"))
                            .font(Typography.detailTitle)
                            .foregroundStyle(Palette.primaryText)
                        Text(verbatim: L("You've been invited to join \(serverName)."))
                            .font(Typography.body)
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    SecureField(L("Choose a password"), text: $password)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .password)
                        .submitLabel(.next)
                        .onSubmit { focus = .confirmation }
                    SecureField(L("Enter it again"), text: $confirmation)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirmation)
                        .submitLabel(.go)
                        .onSubmit { if canAccept { Task { await accept() } } }
                } footer: {
                    if let problem {
                        Text(verbatim: problem).foregroundStyle(Palette.notice)
                    } else {
                        Text(L("This replaces the one-time password in your invitation, which stops working as soon as you set this."))
                    }
                }

                Section {
                    Button {
                        Task { await accept() }
                    } label: {
                        if isAccepting {
                            HStack(spacing: Spacing.s) {
                                ProgressView()
                                Text(L("Joining…"))
                            }
                        } else {
                            Text(L("Join"))
                        }
                    }
                    .disabled(!canAccept)
                }

                if invite.hasExpired() {
                    Section {
                        Label(
                            L("This invitation has expired. Ask whoever sent it for another."),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Palette.notice)
                    }
                }
            }
            .navigationTitle(Text(L("You're invited")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .alert(
                L("Couldn't join"),
                isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
            ) {
                Button(L("OK"), role: .cancel) { failure = nil }
            } message: {
                Text(failure ?? "")
            }
            .onAppear { focus = .password }
        }
        .tint(Palette.accent)
        .interactiveDismissDisabled(isAccepting)
    }

    private func accept() async {
        isAccepting = true
        defer { isAccepting = false }
        do {
            _ = try await environment.session.redeem(invite, choosing: password)
            dismiss()
        } catch {
            failure = (error as? LocalizedError)?.errorDescription
                ?? "The invitation couldn't be accepted."
        }
    }
}

/// Where someone pastes the code they were sent.
///
/// On the first-run screen rather than buried in settings: for an invited
/// person this *is* how they set the app up, and they have no server address
/// to type.
struct PasteInvitationView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var invite: Invite?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Paste your invitation"), text: $code, axis: .vertical)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Typography.timecode)
                } footer: {
                    Text(L("Whoever invited you sent a code beginning with FL1. Paste the whole thing — extra spaces and line breaks don't matter."))
                }

                Section {
                    Button(L("Continue")) { open() }
                        .disabled(code.filter { !$0.isWhitespace }.isEmpty)
                }

                if let failure {
                    Section {
                        Label(verbatim: failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.notice)
                    }
                }
            }
            .navigationTitle(Text(L("Invitation")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .sheet(item: $invite) { InvitationView(invite: $0) }
        }
        .tint(Palette.accent)
    }

    private func open() {
        do {
            invite = try InviteCode.invite(from: code)
            failure = nil
        } catch InviteError.notAnInvite {
            failure = L("That doesn't look like a Firelight invitation.")
        } catch {
            failure = L("That invitation is damaged. Ask for it to be sent again.")
        }
    }
}

/// So an invitation can drive a sheet.
extension Invite: Identifiable {
    public var id: String { username + temporaryPassword }
}

extension Label where Title == Text, Icon == Image {
    /// A label whose text is already localised, which the generated
    /// initialisers do not offer.
    init(verbatim text: String, systemImage: String) {
        self.init { Text(verbatim: text) } icon: { Image(systemName: systemImage) }
    }
}
