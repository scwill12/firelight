import ABSKit
import DesignSystem
import Persistence
import ReaderKit
import SwiftUI

/// Settings.
///
/// Phase 1 adds the real servers and accounts section; the Foundation
/// self-checks stay because they are what tells you, on a device, whether the
/// shared container and Keychain are actually working.
public struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var checks: [FoundationCheck] = []
    @State private var isChecking = true
    @State private var isShowingAddServer = false
    @State private var diagnosticsURL: URL?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                accountsSection
                serversSection
                lockScreenSection
                followAlongSection
                foundationSection
                aboutSection
            }
            .navigationTitle(Text("Settings", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("Done", bundle: .module) }
                }
            }
            .task { await runChecks() }
            .sheet(isPresented: $isShowingAddServer) {
                OnboardingView(isFirstServer: false)
            }
            .sheet(item: Binding(
                get: { diagnosticsURL.map { ExportFile(url: $0) } },
                set: { if $0 == nil { diagnosticsURL = nil } }
            )) { file in
                ShareSheet(items: [file.url])
            }
        }
        .tint(Palette.accent)
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        Section {
            ForEach(environment.session.users) { user in
                Button {
                    Task { await environment.session.switchTo(user: user) }
                } label: {
                    LabeledContent {
                        if user.isActive {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.accent)
                                .accessibilityLabel(Text("Signed in", bundle: .module))
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.hair) {
                            Text(verbatim: user.username)
                                .foregroundStyle(Palette.primaryText)
                            Text(verbatim: serverName(for: user.serverID))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await environment.session.signOut(user: user) }
                    } label: {
                        Label { Text("Sign out", bundle: .module) } icon: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                    }
                }
            }
            if environment.session.users.isEmpty {
                Text("Not signed in", bundle: .module)
                    .foregroundStyle(Palette.secondaryText)
            }
        } header: {
            Text("Accounts", bundle: .module)
        } footer: {
            if environment.session.users.count > 1 {
                Text("Switching takes a moment while Firelight reconnects.", bundle: .module)
            }
        }
    }

    // MARK: - Lock screen

    private var lockScreenSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { environment.player.liveActivityPreference.isOn },
                set: { environment.player.setLiveActivityPreference($0 ? .on : .off) }
            )) {
                Text("Add Firelight's own control", bundle: .module)
            }
        } header: {
            Text("Lock screen", bundle: .module)
        } footer: {
            Text("iOS already shows a Now Playing control while a book is playing. Turn this on to add Firelight's own on top of it — larger buttons, but two controls for one book.", bundle: .module)
        }
    }

    // MARK: - Follow along

    private var followAlongSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { environment.followAlong.isEnabled },
                set: { environment.followAlong.setEnabled($0) }
            )) {
                Text("Show where I'd be in print", bundle: .module)
            }

            if environment.followAlong.isEnabled {
                Picker(selection: Binding(
                    get: { environment.followAlong.device },
                    set: { environment.followAlong.setDevice($0) }
                )) {
                    Text("Kindle", bundle: .module).tag(ReadingDevice.kindle)
                    Text("Kobo", bundle: .module).tag(ReadingDevice.kobo)
                    Text("Nook", bundle: .module).tag(ReadingDevice.nook)
                    Text("Apple Books", bundle: .module).tag(ReadingDevice.appleBooks)
                    Text("A printed book", bundle: .module).tag(ReadingDevice.print)
                } label: {
                    Text("I read on", bundle: .module)
                }

                if environment.followAlong.device == .kindle {
                    Picker(selection: Binding(
                        get: { environment.followAlong.kindleModel },
                        set: { environment.followAlong.setKindleModel($0) }
                    )) {
                        Text("Kindle", bundle: .module).tag(KindleModel.kindle)
                        Text("Paperwhite", bundle: .module).tag(KindleModel.paperwhite)
                        Text("Colorsoft", bundle: .module).tag(KindleModel.colorsoft)
                        Text("Oasis", bundle: .module).tag(KindleModel.oasis)
                        Text("Scribe", bundle: .module).tag(KindleModel.scribe)
                        Text("Kindle app", bundle: .module).tag(KindleModel.app)
                    } label: {
                        Text("Which one", bundle: .module)
                    }
                }
            }
        } header: {
            Text("Following along", bundle: .module)
        } footer: {
            if environment.followAlong.isEnabled {
                Text("A location is the same on every Kindle, so the model only changes where Firelight tells you to look. What makes it accurate is setting the first and last page, and calibrating if the audio opens with a foreword.", bundle: .module)
                Text("The player shows roughly where you'd be in your own copy. Open a book and set how long your copy is — the number differs for every edition. It's an estimate: the audio is matched to the text evenly, so a long foreword will put it out.", bundle: .module)
            } else {
                Text("Shows roughly where you'd be in your own copy of a book while you listen.", bundle: .module)
            }
        }
    }

    // MARK: - Servers

    private var serversSection: some View {
        Section {
            ForEach(environment.session.servers) { server in
                NavigationLink {
                    ServerDetailView(server: server)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.hair) {
                        Text(verbatim: server.displayName)
                        if server.id == environment.session.activeServer?.id {
                            addressLabel
                        }
                    }
                }
            }

            Button {
                isShowingAddServer = true
            } label: {
                Label { Text("Add a server", bundle: .module) } icon: { Image(systemName: "plus") }
            }
        } header: {
            Text("Servers", bundle: .module)
        }
    }

    @ViewBuilder
    private var addressLabel: some View {
        switch environment.session.activeAddress {
        case .local:
            Label { Text("Using the local address", bundle: .module) } icon: { Image(systemName: "house") }
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
        case .remote:
            Label { Text("Using the remote address", bundle: .module) } icon: { Image(systemName: "globe") }
                .font(Typography.caption)
                .foregroundStyle(Palette.secondaryText)
        case nil:
            Label { Text("Not connected", bundle: .module) } icon: { Image(systemName: "wifi.slash") }
                .font(Typography.caption)
                .foregroundStyle(Palette.notice)
        }
    }

    // MARK: - Foundation and About

    private var foundationSection: some View {
        Section {
            if isChecking {
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Checking…", bundle: .module).foregroundStyle(Palette.secondaryText)
                }
            } else {
                ForEach(checks) { check in
                    LabeledContent {
                        Image(systemName: check.outcome.didPass ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check.outcome.didPass ? Palette.accent : Palette.destructive)
                            .accessibilityHidden(true)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.hair) {
                            Text(verbatim: check.name)
                            Text(verbatim: check.outcome.detail)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.secondaryText)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(
                        check.outcome.didPass
                            ? Text("Working", bundle: .module)
                            : Text("Not working", bundle: .module)
                    )
                }
            }
        } header: {
            Text("Foundation", bundle: .module)
        } footer: {
            Text(
                "Firelight shares one container and one Keychain across the app, its widgets, the share extension and the watch app.",
                bundle: .module
            )
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                StatsView()
            } label: {
                Label(L("Stats"), systemImage: "chart.bar")
            }
            NavigationLink {
                HardcoverSettingsView()
            } label: {
                Label(L("Hardcover"), systemImage: "books.vertical.circle")
            }
            NavigationLink {
                StorageView()
            } label: {
                Label(L("Storage"), systemImage: "internaldrive")
            }
            if environment.session.activeUser?.isAdmin == true {
                NavigationLink {
                    AdminView()
                } label: {
                    Label(L("Server admin"), systemImage: "wrench.and.screwdriver")
                }
            }
            Button {
                environment.setKidsMode(true)
            } label: {
                Label(L("Turn on kids mode"), systemImage: "figure.child")
            }
            NavigationLink {
                AppIconPicker()
            } label: {
                Label(L("App icon"), systemImage: "app.badge")
            }
            NavigationLink {
                TipJarView()
            } label: {
                Label(L("Support Firelight"), systemImage: "heart")
            }
            Button {
                Task {
                    let report = await environment.diagnosticsReport()
                    diagnosticsURL = DiagnosticsReport.write(report)
                }
            } label: {
                Label(L("Export diagnostics"), systemImage: "stethoscope")
            }
            LabeledContent { Text(verbatim: Self.versionString) } label: { Text("Version", bundle: .module) }
            LabeledContent { Text(verbatim: environment.device.label) } label: { Text("This device", bundle: .module) }
            if let version = environment.session.activeServerVersion {
                LabeledContent { Text(verbatim: version.description) } label: { Text("Server version", bundle: .module) }
            }
        } header: {
            Text("About", bundle: .module)
        }
    }

    private func serverName(for serverID: UUID) -> String {
        environment.session.servers.first { $0.id == serverID }?.displayName ?? ""
    }

    private func runChecks() async {
        isChecking = true
        let checker = environment.checker
        let results = await Task.detached { checker.run() }.value
        checks = results
        isChecking = false
    }

    static var versionString: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
}

#Preview("Settings") {
    SettingsView().environment(AppEnvironment.preview())
}
