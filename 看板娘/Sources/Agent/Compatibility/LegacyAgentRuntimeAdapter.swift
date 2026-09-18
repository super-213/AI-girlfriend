import Foundation

/// Namespace for constructing the new Core from the legacy app dependencies.
/// Existing `AgentRuntime` remains the source-compatible UI facade during migration.
enum LegacyAgentRuntimeAdapter {
    @MainActor
    static func makeRunner(client: any AgentModelClient) -> AgentRunner {
        AgentRunner(provider: LegacyModelProvider(client: client))
    }

    @MainActor
    static func makeTools<Context: Sendable>(
        registry: AgentToolRegistry
    ) -> [AnyAgentTool<Context>] {
        registry.allTools.map(LegacyToolAdapter<Context>.erase)
    }

    @MainActor
    static func makeTools(registry: AgentToolRegistry) -> [AnyAgentTool<Void>] {
        let legacy = registry.allTools.map(LegacyToolAdapter<Void>.erase)
        return (legacy + registry.allTypedTools).sorted {
            $0.definition.name < $1.definition.name
        }
    }
}
