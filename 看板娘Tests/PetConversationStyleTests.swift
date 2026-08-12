import Foundation
import Testing
@testable import 看板娘

struct PetConversationStyleTests {
    @Test
    func unconfiguredCharacterUsesLegacyStyle() throws {
        try withDefaults { defaults in
            defaults.set("旧角色提示词", forKey: "systemPrompt")
            defaults.set(try JSONEncoder().encode(["主动消息"]), forKey: "staticMessages")

            let style = PetConversationStyleStore.style(for: "character-a", defaults: defaults)

            #expect(style.systemPrompt == "旧角色提示词")
            #expect(style.inputPlaceholder == PetConversationStyle.defaultInputPlaceholder)
            #expect(style.staticMessages == ["主动消息"])
        }
    }

    @Test
    func stylesRemainIndependentForEachCharacter() throws {
        try withDefaults { defaults in
            let first = PetConversationStyle(
                systemPrompt: "风格 A",
                inputPlaceholder: "问 A",
                staticMessages: ["A"]
            )
            let second = PetConversationStyle(
                systemPrompt: "风格 B",
                inputPlaceholder: "问 B",
                staticMessages: ["B"]
            )

            PetConversationStyleStore.save(
                ["character-a": first, "character-b": second],
                defaults: defaults
            )

            #expect(PetConversationStyleStore.style(for: "character-a", defaults: defaults) == first)
            #expect(PetConversationStyleStore.style(for: "character-b", defaults: defaults) == second)
        }
    }

    @Test
    func activeStyleTracksSelectedCharacter() throws {
        try withDefaults { defaults in
            let first = PetConversationStyle(
                systemPrompt: "风格 A",
                inputPlaceholder: "问 A",
                staticMessages: []
            )
            let second = PetConversationStyle(
                systemPrompt: "风格 B",
                inputPlaceholder: "问 B",
                staticMessages: []
            )
            PetConversationStyleStore.save(
                ["character-a": first, "character-b": second],
                defaults: defaults
            )

            defaults.set("character-a", forKey: "selectedPetCharacterID")
            #expect(PetConversationStyleStore.activeStyle(defaults: defaults) == first)

            defaults.set("character-b", forKey: "selectedPetCharacterID")
            #expect(PetConversationStyleStore.activeStyle(defaults: defaults) == second)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "PetConversationStyleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
