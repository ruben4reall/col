import Foundation
import Security

/// Secrets Islet keeps for the user, such as the token of an AI server, in the login Keychain. Never in the settings.
enum Keychain {
    private static let service = "ch.rubencatalao.islet.ai"

    static func token(for account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores a token, or removes it when nil or empty.
    static func setToken(_ token: String?, for account: String) {
        let match: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        SecItemDelete(match as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var item = match
        item[kSecValueData] = Data(token.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
