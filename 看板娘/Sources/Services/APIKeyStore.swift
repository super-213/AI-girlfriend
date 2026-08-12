//
//  APIKeyStore.swift
//  看板娘
//
//  API 密钥的 Keychain 存储与敏感信息脱敏。
//

import Foundation
import Security

protocol APIKeyStoring: Sendable {
    func apiKey(for configurationID: String) throws -> String?
    func setAPIKey(_ apiKey: String, for configurationID: String) throws
    func removeAPIKey(for configurationID: String) throws
}

enum APIKeyStoreError: LocalizedError {
    case invalidData
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Keychain 中的 API Key 数据无效"
        case .keychainFailure(let status):
            return "Keychain 操作失败（错误码 \(status)）"
        }
    }
}

final class KeychainAPIKeyStore: APIKeyStoring, Sendable {
    static let shared = KeychainAPIKeyStore()

    private let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.zhihaojiang.kanbanmusume") + ".api-keys") {
        self.service = service
    }

    func apiKey(for configurationID: String) throws -> String? {
        var query = baseQuery(configurationID: configurationID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.invalidData
        }
        return value
    }

    func setAPIKey(_ apiKey: String, for configurationID: String) throws {
        let data = Data(apiKey.utf8)
        let query = baseQuery(configurationID: configurationID)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychainFailure(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychainFailure(addStatus)
        }
    }

    func removeAPIKey(for configurationID: String) throws {
        let status = SecItemDelete(baseQuery(configurationID: configurationID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(configurationID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: configurationID
        ]
    }
}

enum SensitiveDataRedactor {
    static let placeholder = "<redacted>"

    static func redact(_ value: String, secrets: [String] = []) -> String {
        var result = value
        for secret in secrets where !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: placeholder)
        }

        let patterns = [
            #"(?i)(bearer\s+)[^\s\"',}]+"#,
            #"(?i)((?:api[_-]?key|authorization)\s*[:=]\s*[\"']?)[^\s\"',}&]+"#,
            #"\b(?:sk|key)-[A-Za-z0-9_\-]{8,}\b"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "$1" + placeholder
            )
        }
        return result
    }
}
