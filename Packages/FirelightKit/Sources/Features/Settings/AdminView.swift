import ABSKit
import DesignSystem
import SwiftUI

/// Server administration, for admin accounts only.
///
/// Read-mostly on purpose: this is a client, and the server's own web UI is a
/// better place to do anything destructive. What is here is what you reach for
/// from a phone — kick off a scan, see who is listening, check the version.
struct AdminView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tasks: [ABSTask] = []
    @State private var users: [ABSAdminUser] = []
    @State private var sessions: [ABSListeningSession] = []
    @State private var isWorking = false
    @State private var message: String?
    @State private var isShowingInvite = false

    var body: some View {
        List {
            Section {
                ForEach(environment.library.libraries) { library in
                    Button {
                        Task { await scan(libraryID: library.id) }
                    } label: {
                        LabeledContent {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Palette.accent)
                        } label: {
                            Text(verbatim: library.name)
                        }
                    }
                    .disabled(isWorking)
                }
            } header: {
                Text(L("Scan a library"))
            } footer: {
                if let message {
                    Text(verbatim: message).foregroundStyle(Palette.secondaryText)
                }
            }

            if !tasks.isEmpty {
                Section {
                    ForEach(tasks) { task in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: task.title ?? task.action ?? L("Task"))
                                .foregroundStyle(Palette.primaryText)
                            if let description = task.description {
                                Text(verbatim: description)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                            if task.isFailed == true, let error = task.error {
                                Text(verbatim: error)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.destructive)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text(L("Jobs"))
                }
            }

            Section {
                if sessions.isEmpty {
                    Text(L("Nobody is listening right now."))
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: session.displayTitle ?? L("Unknown"))
                                .foregroundStyle(Palette.primaryText)
                                .lineLimit(1)
                            Text(verbatim: [session.displayAuthor, session.mediaPlayer]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } header: {
                Text(L("Listening now"))
            }

            Section {
                ForEach(users) { user in
                    LabeledContent {
                        Text(verbatim: user.type ?? "")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.secondaryText)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: user.username)
                            if let lastSeen = user.lastSeen {
                                Text(verbatim: L("Last seen \(lastSeen.formatted(.relative(presentation: .named)))"))
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.secondaryText)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    isShowingInvite = true
                } label: {
                    Label(L("Invite someone"), systemImage: "person.badge.plus")
                }
            } header: {
                Text(L("Users"))
            } footer: {
                Text(L("An invited account can download and read, and nothing else."))
            }

            Section {
                LabeledContent {
                    Text(verbatim: environment.session.activeServerVersion?.description ?? L("Unknown"))
                } label: {
                    Text(L("Server version"))
                }
            } header: {
                Text(L("Server"))
            }
        }
        .navigationTitle(Text(L("Server admin")))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .sheet(isPresented: $isShowingInvite, onDismiss: { Task { await load() } }) {
            InviteSomeoneView()
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = environment.session.client() else { return }
        async let tasks = try? client.tasks()
        async let users = try? client.users()
        async let sessions = try? client.listeningSessions()
        self.tasks = (await tasks ?? []).filter { $0.isFinished != true }
        self.users = await users ?? []
        self.sessions = await sessions ?? []
    }

    private func scan(libraryID: String) async {
        guard let client = environment.session.client() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.scanLibrary(libraryID: libraryID)
            message = L("Scan started.")
            await load()
        } catch {
            message = L("Couldn't start a scan. Admin permission is needed.")
        }
    }
}
