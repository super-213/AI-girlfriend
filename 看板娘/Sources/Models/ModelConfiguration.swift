//
//  ModelConfiguration.swift
//  看板娘
//
//  可持久化的 AI 服务配置与旧版单配置迁移。
//

import Foundation

enum ModelProvider: String, CaseIterable, Codable, Identifiable {
    case zhipu
    case openAICompatible = "qwen"
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhipu: return "智谱清言"
        case .openAICompatible: return "OpenAI-Compatible"
        case .ollama: return "Ollama"
        }
    }

    var shortName: String {
        switch self {
        case .zhipu: return "智谱"
        case .openAICompatible: return "兼容接口"
        case .ollama: return "本地"
        }
    }

    var systemImage: String {
        switch self {
        case .zhipu: return "sparkles"
        case .openAICompatible: return "point.3.connected.trianglepath.dotted"
        case .ollama: return "desktopcomputer"
        }
    }
}

struct ModelConfiguration: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var provider: String
    var aiModel: String
    var apiUrl: String
    /// 仅供编辑和请求期间使用；Codable 持久化时不会编码此字段。
    var apiKey: String

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, aiModel, apiUrl
        case apiKey // 仅用于解码旧版明文数据。
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        provider: String,
        aiModel: String,
        apiUrl: String,
        apiKey: String
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.aiModel = aiModel
        self.apiUrl = apiUrl
        self.apiKey = apiKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(String.self, forKey: .provider)
        aiModel = try container.decode(String.self, forKey: .aiModel)
        apiUrl = try container.decode(String.self, forKey: .apiUrl)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(provider, forKey: .provider)
        try container.encode(aiModel, forKey: .aiModel)
        try container.encode(apiUrl, forKey: .apiUrl)
    }

    var providerKind: ModelProvider {
        get { ModelProvider(rawValue: provider) ?? .openAICompatible }
        set { provider = newValue.rawValue }
    }

    var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return false }
        return !trimmedName.isEmpty && !trimmedModel.isEmpty
    }

    func normalized() -> ModelConfiguration {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.aiModel = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        result.apiUrl = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        result.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    static func preset(for provider: ModelProvider) -> ModelConfiguration {
        switch provider {
        case .zhipu:
            return ModelConfiguration(
                name: "智谱 GLM",
                provider: provider.rawValue,
                aiModel: "glm-4v-flash",
                apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
                apiKey: ""
            )
        case .openAICompatible:
            return ModelConfiguration(
                name: "OpenAI 兼容服务",
                provider: provider.rawValue,
                aiModel: "qwen-plus",
                apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                apiKey: ""
            )
        case .ollama:
            return ModelConfiguration(
                name: "Ollama 本地",
                provider: provider.rawValue,
                aiModel: "qwen2.5",
                apiUrl: "http://localhost:11434/api/chat",
                apiKey: "ollama"
            )
        }
    }

    static func migratedLegacy(
        provider: String,
        aiModel: String,
        apiUrl: String,
        apiKey: String
    ) -> ModelConfiguration {
        let name: String
        let loweredURL = apiUrl.lowercased()

        if provider == ModelProvider.ollama.rawValue {
            name = "Ollama 本地"
        } else if loweredURL.contains("localhost:1234") || loweredURL.contains("127.0.0.1:1234") {
            name = "LM Studio 本地"
        } else if loweredURL.contains("dashscope") || loweredURL.contains("aliyuncs") {
            name = "通义千问云端"
        } else if provider == ModelProvider.zhipu.rawValue {
            name = "智谱 GLM"
        } else {
            name = aiModel.isEmpty ? "OpenAI 兼容服务" : aiModel
        }

        return ModelConfiguration(
            name: name,
            provider: provider,
            aiModel: aiModel,
            apiUrl: apiUrl,
            apiKey: apiKey
        )
    }
}

struct ModelConfigurationLibrary: Equatable {
    static let configurationsKey = "modelConfigurations"
    static let activeConfigurationIDKey = "activeModelConfigurationID"

    var configurations: [ModelConfiguration]
    var activeConfigurationID: String

    static func load(
        from defaults: UserDefaults = .standard,
        legacyConfiguration: ModelConfiguration,
        keyStore: APIKeyStoring = KeychainAPIKeyStore.shared
    ) throws -> ModelConfigurationLibrary {
        let library: ModelConfigurationLibrary
        if let data = defaults.data(forKey: configurationsKey),
           let configurations = try? JSONDecoder().decode([ModelConfiguration].self, from: data),
           !configurations.isEmpty {
            let storedActiveID = defaults.string(forKey: activeConfigurationIDKey)
            let activeID = storedActiveID.flatMap { candidate in
                configurations.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? configurations[0].id
            library = ModelConfigurationLibrary(
                configurations: configurations,
                activeConfigurationID: activeID
            )
        } else {
            let migrated = legacyConfiguration.normalized()
            library = ModelConfigurationLibrary(
                configurations: [migrated],
                activeConfigurationID: migrated.id
            )
        }

        var migratedLibrary = library
        let legacyDefaultsKey = defaults.string(forKey: "apiKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for index in migratedLibrary.configurations.indices {
            let configurationID = migratedLibrary.configurations[index].id
            var plaintext = migratedLibrary.configurations[index].apiKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if configurationID == migratedLibrary.activeConfigurationID,
               let legacyDefaultsKey,
               !legacyDefaultsKey.isEmpty {
                plaintext = legacyDefaultsKey
            }

            if !plaintext.isEmpty {
                try keyStore.setAPIKey(plaintext, for: configurationID)
            }
            migratedLibrary.configurations[index].apiKey = try keyStore.apiKey(for: configurationID) ?? ""
        }

        // 只有所有 Keychain 写入成功后，才覆盖旧 JSON 并删除 UserDefaults 明文。
        try migratedLibrary.persistMetadata(to: defaults)
        defaults.removeObject(forKey: "apiKey")
        return migratedLibrary
    }

    func save(
        to defaults: UserDefaults = .standard,
        keyStore: APIKeyStoring = KeychainAPIKeyStore.shared
    ) throws {
        guard !configurations.isEmpty,
              configurations.contains(where: { $0.id == activeConfigurationID }) else { return }

        let previousIDs: Set<String>
        if let data = defaults.data(forKey: Self.configurationsKey),
           let previous = try? JSONDecoder().decode([ModelConfiguration].self, from: data) {
            previousIDs = Set(previous.map(\.id))
        } else {
            previousIDs = []
        }

        for configuration in configurations {
            let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if apiKey.isEmpty {
                try keyStore.removeAPIKey(for: configuration.id)
            } else {
                try keyStore.setAPIKey(apiKey, for: configuration.id)
            }
        }

        try persistMetadata(to: defaults)
        defaults.removeObject(forKey: "apiKey")

        for deletedID in previousIDs.subtracting(configurations.map(\.id)) {
            try keyStore.removeAPIKey(for: deletedID)
        }
    }

    static func synchronizeActiveConfiguration(
        in defaults: UserDefaults = .standard,
        legacyConfiguration: ModelConfiguration,
        keyStore: APIKeyStoring = KeychainAPIKeyStore.shared
    ) throws {
        var library = try load(from: defaults, legacyConfiguration: legacyConfiguration, keyStore: keyStore)
        guard let index = library.configurations.firstIndex(where: { $0.id == library.activeConfigurationID }) else {
            return
        }

        var updated = legacyConfiguration.normalized()
        updated.id = library.configurations[index].id
        updated.name = library.configurations[index].name
        library.configurations[index] = updated
        try library.save(to: defaults, keyStore: keyStore)
    }

    private func persistMetadata(to defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(configurations)
        defaults.set(data, forKey: Self.configurationsKey)
        defaults.set(activeConfigurationID, forKey: Self.activeConfigurationIDKey)
    }
}
