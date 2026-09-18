import Foundation

struct HandoffArguments: Codable, Equatable, Sendable {
    let reason: String
    let metadata: JSONValue?

    init(reason: String, metadata: JSONValue? = nil) {
        self.reason = reason
        self.metadata = metadata
    }
}

struct AgentHandoff<Context: Sendable, Output: Sendable>: Sendable {
    let targetAgentID: String
    let targetAgentName: String
    let description: String
    let metadata: JSONValue?

    private let resolveValue: @Sendable () -> AgentDefinition<Context, Output>
    private let filterValue: @Sendable ([AgentItem]) -> [AgentItem]

    init(
        target: AgentDefinition<Context, Output>,
        description: String,
        metadata: JSONValue? = nil,
        historyFilter: @escaping @Sendable ([AgentItem]) -> [AgentItem] = { $0 }
    ) {
        targetAgentID = target.id
        targetAgentName = target.name
        self.description = description
        self.metadata = metadata
        resolveValue = { target }
        filterValue = historyFilter
    }

    init(
        targetAgentID: String,
        targetAgentName: String,
        description: String,
        metadata: JSONValue? = nil,
        historyFilter: @escaping @Sendable ([AgentItem]) -> [AgentItem] = { $0 },
        resolve: @escaping @Sendable () -> AgentDefinition<Context, Output>
    ) {
        self.targetAgentID = targetAgentID
        self.targetAgentName = targetAgentName
        self.description = description
        self.metadata = metadata
        resolveValue = resolve
        filterValue = historyFilter
    }

    var toolName: String { "handoff_to_\(Self.normalized(targetAgentID))" }

    var toolDefinition: ToolDefinition {
        ToolDefinition(
            name: toolName,
            description: description,
            parameters: .object([
                "type": .string("object"),
                "properties": .object([
                    "reason": .object([
                        "type": .string("string"),
                        "description": .string("为什么需要将后续对话交给该 Agent")
                    ]),
                    "metadata": .object(["type": .string("object")])
                ]),
                "required": .array([.string("reason")]),
                "additionalProperties": .bool(false)
            ])
        )
    }

    func resolve() -> AgentDefinition<Context, Output> { resolveValue() }
    func filterHistory(_ items: [AgentItem]) -> [AgentItem] { filterValue(items) }

    private static func normalized(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "_"
        }
        return String(scalars)
    }
}

extension AgentDefinition {
    func resolvingAgent(id: String, maximumDepth: Int = 16) -> AgentDefinition<Context, Output>? {
        resolveAgent(id: id, visited: [], remainingDepth: maximumDepth)
    }

    private func resolveAgent(
        id: String,
        visited: Set<String>,
        remainingDepth: Int
    ) -> AgentDefinition<Context, Output>? {
        guard remainingDepth >= 0, !visited.contains(self.id) else { return nil }
        if self.id == id { return self }
        var nextVisited = visited
        nextVisited.insert(self.id)
        for handoff in handoffs {
            let target = handoff.resolve()
            if let match = target.resolveAgent(
                id: id,
                visited: nextVisited,
                remainingDepth: remainingDepth - 1
            ) {
                return match
            }
        }
        return nil
    }
}
