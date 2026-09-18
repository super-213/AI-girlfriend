import Foundation

/// Bridges the callback-based APIManager/AgentModelClient into the Core provider protocol.
final class LegacyModelProvider: AgentModelProvider, @unchecked Sendable {
    let id: String
    let capabilities: ModelCapabilities
    private let client: any AgentModelClient
    private let normalizeToolCall: @MainActor @Sendable (AgentToolCall) -> AgentToolCall

    @MainActor
    init(
        id: String = "legacy-chat-provider",
        capabilities: ModelCapabilities = .chatCompletions,
        client: any AgentModelClient,
        normalizeToolCall: @escaping @MainActor @Sendable (AgentToolCall) -> AgentToolCall = { $0 }
    ) {
        self.id = id
        self.capabilities = capabilities
        self.client = client
        self.normalizeToolCall = normalizeToolCall
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [client] in
                client.sendAgentStreamRequest(
                    messages: AgentItemLegacyCodec.messages(from: request.items),
                    tools: request.tools.map(Self.legacyDefinition),
                    purpose: request.purpose,
                    onReceive: { continuation.yield(.textDelta($0)) },
                    onComplete: { response in
                        continuation.yield(.completed(ModelResponse(
                            content: response.content,
                            toolCalls: response.toolCalls.map(self.normalizeToolCall).map {
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
            continuation.onTermination = { @Sendable termination in
                guard case .cancelled = termination else { return }
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

}
