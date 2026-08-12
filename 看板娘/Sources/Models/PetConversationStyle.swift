//
//  PetConversationStyle.swift
//  看板娘
//
//  与桌宠角色绑定的对话风格及其持久化。
//

import Foundation

struct PetConversationStyle: Codable, Equatable {
    static let defaultInputPlaceholder = "我会帮助指挥官解决问题！"

    var systemPrompt: String
    var inputPlaceholder: String
    var staticMessages: [String]

    static let `default` = PetConversationStyle(
        systemPrompt: PreferencesData.default.systemPrompt,
        inputPlaceholder: defaultInputPlaceholder,
        staticMessages: []
    )
}

enum PetConversationStyleStore {
    static let storageKey = "petConversationStyles.v1"

    static func style(
        for characterID: String,
        defaults: UserDefaults = .standard
    ) -> PetConversationStyle {
        load(from: defaults)[characterID] ?? legacyStyle(from: defaults)
    }

    static func activeStyle(defaults: UserDefaults = .standard) -> PetConversationStyle {
        let characterID = defaults.string(forKey: "selectedPetCharacterID") ?? puppetBear.id
        return style(for: characterID, defaults: defaults)
    }

    static func styles(
        for characterIDs: [String],
        defaults: UserDefaults = .standard
    ) -> [String: PetConversationStyle] {
        let saved = load(from: defaults)
        let fallback = legacyStyle(from: defaults)
        return Dictionary(uniqueKeysWithValues: characterIDs.map { id in
            (id, saved[id] ?? fallback)
        })
    }

    static func save(
        _ styles: [String: PetConversationStyle],
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(styles) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func update(
        _ style: PetConversationStyle,
        for characterID: String,
        defaults: UserDefaults = .standard
    ) {
        var saved = load(from: defaults)
        saved[characterID] = style
        save(saved, defaults: defaults)
    }

    static func removeStyle(
        for characterID: String,
        defaults: UserDefaults = .standard
    ) {
        var saved = load(from: defaults)
        guard saved.removeValue(forKey: characterID) != nil else { return }
        save(saved, defaults: defaults)
    }

    private static func load(from defaults: UserDefaults) -> [String: PetConversationStyle] {
        guard let data = defaults.data(forKey: storageKey),
              let styles = try? JSONDecoder().decode([String: PetConversationStyle].self, from: data) else {
            return [:]
        }
        return styles
    }

    private static func legacyStyle(from defaults: UserDefaults) -> PetConversationStyle {
        let systemPrompt = defaults.string(forKey: "systemPrompt")
            ?? PreferencesData.default.systemPrompt
        var staticMessages: [String] = []
        if let data = defaults.data(forKey: "staticMessages"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            staticMessages = decoded
        }
        return PetConversationStyle(
            systemPrompt: systemPrompt,
            inputPlaceholder: PetConversationStyle.defaultInputPlaceholder,
            staticMessages: staticMessages
        )
    }
}
