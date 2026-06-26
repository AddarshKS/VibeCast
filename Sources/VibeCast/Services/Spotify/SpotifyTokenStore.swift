import Foundation
import Security

final class SpotifyTokenStore {
    private let service = "\(AppConfig.bundleID).spotify"
    private let account = "oauth-token"
    private let accessGroup: String? = nil

    func load() throws -> SpotifyToken? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw SpotifyAuthError.keychain(status)
        }

        return try JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    func save(_ token: SpotifyToken) throws {
        let data = try JSONEncoder().encode(token)
        var query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SpotifyAuthError.keychain(addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw SpotifyAuthError.keychain(status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SpotifyAuthError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}
