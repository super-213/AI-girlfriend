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
    var apiKey: String

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
                apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
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
        legacyConfiguration: ModelConfiguration
    ) -> ModelConfigurationLibrary {
        if let data = defaults.data(forKey: configurationsKey),
           let configurations = try? JSONDecoder().decode([ModelConfiguration].self, from: data),
           !configurations.isEmpty {
            let storedActiveID = defaults.string(forKey: activeConfigurationIDKey)
            let activeID = storedActiveID.flatMap { candidate in
                configurations.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? configurations[0].id
            return ModelConfigurationLibrary(
                configurations: configurations,
                activeConfigurationID: activeID
            )
        }

        let migrated = legacyConfiguration.normalized()
        let library = ModelConfigurationLibrary(
            configurations: [migrated],
            activeConfigurationID: migrated.id
        )
        library.save(to: defaults)
        return library
    }

    func save(to defaults: UserDefaults = .standard) {
        guard !configurations.isEmpty,
              configurations.contains(where: { $0.id == activeConfigurationID }),
              let data = try? JSONEncoder().encode(configurations) else { return }

        defaults.set(data, forKey: Self.configurationsKey)
        defaults.set(activeConfigurationID, forKey: Self.activeConfigurationIDKey)
    }

    static func synchronizeActiveConfiguration(
        in defaults: UserDefaults = .standard,
        legacyConfiguration: ModelConfiguration
    ) {
        var library = load(from: defaults, legacyConfiguration: legacyConfiguration)
        guard let index = library.configurations.firstIndex(where: { $0.id == library.activeConfigurationID }) else {
            return
        }

        var updated = legacyConfiguration.normalized()
        updated.id = library.configurations[index].id
        updated.name = library.configurations[index].name
        library.configurations[index] = updated
        library.save(to: defaults)
    }
}
