import ABSKit
import Foundation
import SwiftData

/// A signed-in account, as a value the UI can hold.
///
/// SwiftData models are not `Sendable`, so nothing outside this actor ever sees
/// a `UserRecord` or a `ServerRecord` — they cross the boundary as these.
public struct UserSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public let serverID: UUID
    public let absUserID: String
    public let username: String
    public let accountType: String?
    public let defaultLibraryID: String?
    public let isActive: Bool

    public var isAdmin: Bool { accountType == "admin" || accountType == "root" }

    public init(
        id: String,
        serverID: UUID,
        absUserID: String,
        username: String,
        accountType: String?,
        defaultLibraryID: String?,
        isActive: Bool
    ) {
        self.id = id
        self.serverID = serverID
        self.absUserID = absUserID
        self.username = username
        self.accountType = accountType
        self.defaultLibraryID = defaultLibraryID
        self.isActive = isActive
    }
}

/// Reads and writes the servers and accounts the user has configured.
@ModelActor
public actor ServerStore {
    // MARK: - Servers

    public func servers() throws -> [ServerDescriptor] {
        let descriptor = FetchDescriptor<ServerRecord>(sortBy: [SortDescriptor(\.addedAt)])
        return try modelContext.fetch(descriptor).map(Self.descriptor(from:))
    }

    public func server(id: UUID) throws -> ServerDescriptor? {
        try record(id: id).map(Self.descriptor(from:))
    }

    @discardableResult
    public func addServer(
        displayName: String,
        localURL: URL?,
        remoteURL: URL,
        serverVersion: String?
    ) throws -> ServerDescriptor {
        let record = ServerRecord(
            displayName: displayName,
            localURLString: localURL?.absoluteString,
            remoteURLString: remoteURL.absoluteString,
            serverVersionString: serverVersion
        )
        modelContext.insert(record)
        try modelContext.save()
        return Self.descriptor(from: record)
    }

    public func updateServer(
        id: UUID,
        displayName: String? = nil,
        localURL: URL?? = nil,
        remoteURL: URL? = nil,
        serverVersion: String?? = nil
    ) throws {
        guard let record = try record(id: id) else { return }
        if let displayName { record.displayName = displayName }
        if let localURL { record.localURLString = localURL?.absoluteString }
        if let remoteURL { record.remoteURLString = remoteURL.absoluteString }
        if let serverVersion { record.serverVersionString = serverVersion }
        try modelContext.save()
    }

    /// Remembers which address answered, so the next launch tries it first.
    public func recordConnection(id: UUID, address: ActiveAddress, serverVersion: String?) throws {
        guard let record = try record(id: id) else { return }
        record.lastActiveAddressRaw = address.rawValue
        record.lastConnectedAt = .now
        if let serverVersion { record.serverVersionString = serverVersion }
        try modelContext.save()
    }

    public func removeServer(id: UUID) throws {
        guard let record = try record(id: id) else { return }
        for user in try users(forServerID: id) {
            if let userRecord = try userRecord(compositeID: user.id) {
                modelContext.delete(userRecord)
            }
        }
        modelContext.delete(record)
        try modelContext.save()
    }

    // MARK: - Users

    public func users(forServerID serverID: UUID) throws -> [UserSummary] {
        let descriptor = FetchDescriptor<UserRecord>(
            predicate: #Predicate { $0.serverID == serverID },
            sortBy: [SortDescriptor(\.username)]
        )
        return try modelContext.fetch(descriptor).map(Self.summary(from:))
    }

    public func allUsers() throws -> [UserSummary] {
        try modelContext.fetch(FetchDescriptor<UserRecord>(sortBy: [SortDescriptor(\.username)]))
            .map(Self.summary(from:))
    }

    public func activeUser() throws -> UserSummary? {
        let descriptor = FetchDescriptor<UserRecord>(predicate: #Predicate { $0.isActive })
        return try modelContext.fetch(descriptor).first.map(Self.summary(from:))
    }

    /// Records a sign-in and makes that account the active one.
    @discardableResult
    public func signIn(
        serverID: UUID,
        user: ABSUser,
        defaultLibraryID: String?
    ) throws -> UserSummary {
        let compositeID = "\(serverID.uuidString):\(user.id)"
        let record: UserRecord
        if let existing = try userRecord(compositeID: compositeID) {
            record = existing
            record.username = user.username
            record.accountType = user.type
            record.defaultLibraryID = defaultLibraryID
            record.lastSignedInAt = .now
        } else {
            record = UserRecord(
                serverID: serverID,
                absUserID: user.id,
                username: user.username,
                accountType: user.type,
                defaultLibraryID: defaultLibraryID
            )
            modelContext.insert(record)
        }
        try setActive(compositeID: compositeID)
        return Self.summary(from: record)
    }

    /// Exactly one account is active at a time.
    public func setActive(compositeID: String) throws {
        for record in try modelContext.fetch(FetchDescriptor<UserRecord>()) {
            record.isActive = (record.compositeID == compositeID)
        }
        try modelContext.save()
    }

    public func signOut(compositeID: String) throws {
        guard let record = try userRecord(compositeID: compositeID) else { return }
        modelContext.delete(record)
        try modelContext.save()
    }

    // MARK: - Private

    private func record(id: UUID) throws -> ServerRecord? {
        let descriptor = FetchDescriptor<ServerRecord>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    private func userRecord(compositeID: String) throws -> UserRecord? {
        let descriptor = FetchDescriptor<UserRecord>(predicate: #Predicate { $0.compositeID == compositeID })
        return try modelContext.fetch(descriptor).first
    }

    private static func descriptor(from record: ServerRecord) -> ServerDescriptor {
        ServerDescriptor(
            id: record.id,
            displayName: record.displayName,
            localURL: record.localURLString.flatMap(URL.init(string:)),
            remoteURL: URL(string: record.remoteURLString) ?? URL(string: "https://invalid.invalid")!,
            trustedCertificate: nil
        )
    }

    private static func summary(from record: UserRecord) -> UserSummary {
        UserSummary(
            id: record.compositeID,
            serverID: record.serverID,
            absUserID: record.absUserID,
            username: record.username,
            accountType: record.accountType,
            defaultLibraryID: record.defaultLibraryID,
            isActive: record.isActive
        )
    }
}
