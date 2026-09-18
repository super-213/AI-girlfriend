import Foundation

/// Bridges the callback-based APIManager/AgentModelClient into the Core provider protocol.
final class LegacyModelProvider: AgentModelProvider, @unchecked Sendable {
    let id: String
    let capabilities: ModelCapabilities
    private let client: any AgentModelClient

    @MainActor
    init(
        id: String = "legacy-chat-provider",
        capabilities: ModelCapabilities = .chatCompletions,
        client: any AgentModelClient
    ) {
        self.id = id
        self.capabilities = capabilities
        self.client = client
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [client] in
                client.sendAgentStreamRequest(
                    messages: Self.legacyMessages(from: request.items),
                    tools: request.tools.map(Self.legacyDefinition),
                    purpose: .conversation,
                    onReceive: { continuation.yield(.textDelta($0)) },
                    onComplete: { response in
                        continuation.yield(.completed(ModelResponse(
                            content: response.content,
                            toolCalls: response.toolCalls.map {
                                ToolCallItem(id: $0.id, name: $0.name, arguments: $0.arguments)
                            },
                            usage: response.usage.map {
                                AgentUsage(
                                    inputTokens: $0.promptTokens,
                                    outputTokens: $0.completionTokens ?? 0,
                                    totalTokens: $0.totalTokens
                                        ?? ($0.promptTokens + ($0.completionTokens ?? 0))
                                )
                            }
                        )))
                        continuation.finish()
                    },
                    onError: { error in continuation.finish(throwing: error) }
                )
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [client = self.client] in client.cancelStreamRequest() }
            }
        }
    }

    func cancel(runID: UUID) async {
        await MainActor.run { client.cancelStreamRequest() }
    }

    @MainActor
    private static func legacyDefinition(_ definition: ToolDefinition) -> AgentToolDefinition {
        AgentToolDefinition(
            name: definition.name,
            description: definition.description,
            parameters: definition.parameters.foundationValue as? [String: Any] ?? [:]
        )
    }

    @MainActor
    private static func legacyMessages(from items: [AgentItem]) -> [AgentMessage] {
        var messages: [AgentMessage] = []
        for item in items {
            switch item {
            case .message(let item):
                switch item.role {
                case .system:
                    messages.append(.system(item.content ?? ""))
                case .user:
                    messages.append(.user(item.content ?? "", imagePaths: item.imagePaths))
                case .assistant:
                    messages.append(.assistant(content: item.content))
                }
            case .toolCall(let item):
                let call = AgentToolCall(id: item.id, name: item.name, arguments: item.arguments)
                if messages.last?.role == .assistant {
                    var calls = messages[messages.count - 1].toolCalls ?? []
                    calls.append(call)
                    messages[messages.count - 1].toolCalls = calls
                } else {
                    messages.append(.assistant(content: nil, toolCalls: [call]))
                }
            case .toolResult(let item):
                messages.append(.tool(
                    call: AgentToolCall(
                        id: item.toolCallID,
                        name: item.toolName,
                        arguments: "{}"
                    ),
                    content: item.content
                ))
            case .compaction(let item):
                messages.append(.contextSummary(item.summary))
            case .handoff, .guardrail, .approval:
                continue
            }
        }
        return messages
    }
}
