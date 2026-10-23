import Foundation
import Security

public enum KeychainError: Error, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// The only place a token, password or custom proxy header is stored.
///
/// Shared with the widgets, the share extension and the watch app through the
/// Keychain access group, so every target reads the same credentials.
///
/// Two deliberate choices:
///  - `AfterFirstUnlockThisDeviceOnly`: background audio, background downloads
///    and background sync all need the access token while the device is locked,
///    but a credential for someone's private server has no business being
///    carried to another device by an iCloud Keychain backup.
///  - No value or key is ever logged, and errors carry only an `OSStatus`.
public struct KeychainStore: Sendable {
    public let service: String
    public let accessGroup: String?

    public init(service: String = KeychainStore.defaultService, accessGroup: String? = KeychainStore.sharedAccessGroup) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public static let defaultService = "com.colewilliams.firelight"

    /// The shared access group, assembled from the team prefix that the build
    /// substitutes into `AppIdentifierPrefix` in each target's Info.plist.
    /// `$(AppIdentifierPrefix)` is a build-time variable, so there is no other
    /// way to learn the team prefix at runtime.
    public static var sharedAccessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              prefix.hasSuffix("."), prefix.count > 1
        else { return nil }
        return prefix + "com.colewilliams.firelight.shared"
    }

    // MARK: - Data

    public func setData(_ data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let update = attributes.reduce(into: [String: Any]()) { $0[$1.key as String] = $1.value }
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(updateStatus) }
        case errSecItemNotFound:
            for (attributeKey, value) in attributes { query[attributeKey as String] = value }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes every item this store owns. Used by sign-out and by "forget this
    /// server", never by anything automatic.
    public func removeAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Codable

    public func set<T: Encodable>(_ value: T, for key: String) throws {
        guard let data = try? JSONEncoder().encode(value) else { throw KeychainError.encodingFailed }
        try setData(data, for: key)
    }

    public func value<T: Decodable>(_: T.Type, for key: String) throws -> T? {
        guard let data = try data(for: key) else { return nil }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            // A value we can no longer read is a value we should not keep.
            try remove(key)
            return nil
        }
        return decoded
    }

    public func setString(_ string: String, for key: String) throws {
        guard let data = string.data(using: .utf8) else { throw KeychainError.encodingFailed }
        try setData(data, for: key)
    }

    public func string(for key: String) throws -> String? {
        guard let data = try data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

/// The keys Firelight stores, so no two call sites can disagree on a string.
public enum KeychainKey {
    public static func accessToken(serverID: UUID) -> String { "server.\(serverID.uuidString).accessToken" }
    public static func refreshToken(serverID: UUID) -> String { "server.\(serverID.uuidString).refreshToken" }
    public static func legacyToken(serverID: UUID) -> String { "server.\(serverID.uuidString).legacyToken" }
    public static func customHeaders(serverID: UUID) -> String { "server.\(serverID.uuidString).customHeaders" }
    public static func trustedCertificate(serverID: UUID) -> String { "server.\(serverID.uuidString).trustedCertificate" }
}
