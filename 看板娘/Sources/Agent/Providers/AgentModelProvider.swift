import Foundation

struct ModelRequest: Sendable {
    let runID: UUID
    let agentID: String
    let model: AgentModelConfiguration
    let items: [AgentItem]
    let tools: [ToolDefinition]
    let outputSchema: AgentOutputSchema?

    init(
        runID: UUID,
        agentID: String,
        model: AgentModelConfiguration,
        items: [AgentItem],
        tools: [ToolDefinition],
        outputSchema: AgentOutputSchema? = nil
    ) {
        self.runID = runID
        self.agentID = agentID
        self.model = model
        self.items = items
        self.tools = tools
        self.outputSchema = outputSchema
    }
}

struct ModelResponse: Codable, Equatable, Sendable {
    let id: String?
    let content: String
    let toolCalls: [ToolCallItem]
    let usage: AgentUsage?

    init(
        id: String? = nil,
        content: String,
        toolCalls: [ToolCallItem] = [],
        usage: AgentUsage? = nil
    ) {
        self.id = id
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

enum ModelStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case completed(ModelResponse)
}

protocol AgentModelProvider: Sendable {
    var id: String { get }
    var capabilities: ModelCapabilities { get }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error>
    func cancel(runID: UUID) async
}

extension AgentModelProvider {
    func cancel(runID: UUID) async {}
}
