//
//  KeychainStore.swift
//  Consnow
//
//  Minimal Keychain wrapper for the JWT (Android kept it in DataStore;
//  on iOS the Keychain is the right place for secrets, not UserDefaults).
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.consnow.ios"

    enum ReadResult: Equatable {
        case value(String)
        case notFound
        /// The phone restarted and hasn't been unlocked yet: the Keychain is still
        /// encrypted. The value may well exist; try again after the first unlock.
        case lockedUntilFirstUnlock
        case failed(OSStatus)
    }

    static func read(_ key: String) -> String? {
        if case .value(let value) = readResult(key) { return value }
        return nil
    }

    static func readResult(_ key: String) -> ReadResult {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                return .failed(status)
            }
            return .value(value)
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed:
            return .lockedUntilFirstUnlock
        default:
            return .failed(status)
        }
    }

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // readable after first unlock so background syncs still have the token
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add.merge(attributes) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
