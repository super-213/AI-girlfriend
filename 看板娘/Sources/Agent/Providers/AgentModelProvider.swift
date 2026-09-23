import Foundation

struct ModelRequest: Sendable {
    let runID: UUID
    let agentID: String
    let model: AgentModelConfiguration
    let items: [AgentItem]
    let tools: [ToolDefinition]
    let outputSchema: AgentOutputSchema?
    let purpose: AgentRequestPurpose

    init(
        runID: UUID,
        agentID: String,
        model: AgentModelConfiguration,
        items: [AgentItem],
        tools: [ToolDefinition],
        outputSchema: AgentOutputSchema? = nil,
        purpose: AgentRequestPurpose = .conversation
    ) {
        self.runID = runID
        self.agentID = agentID
        self.model = model
        self.items = items
        self.tools = tools
        self.outputSchema = outputSchema
        self.purpose = purpose
    }
}

struct ModelResponse: Codable, Equatable, Sendable {
    let id: String?
    let content: String
    let toolCalls: [ToolCallItem]
    let usage: AgentUsage?
    let responseOutput: [JSONValue]

    init(
        id: String? = nil,
        content: String,
        toolCalls: [ToolCallItem] = [],
        usage: AgentUsage? = nil,
        responseOutput: [JSONValue] = []
    ) {
        self.id = id
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
        self.responseOutput = responseOutput
    }

    private enum CodingKeys: String, CodingKey {
        case id, content, toolCalls, usage, responseOutput
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        toolCalls = try container.decode([ToolCallItem].self, forKey: .toolCalls)
        usage = try container.decodeIfPresent(AgentUsage.self, forKey: .usage)
        responseOutput = try container.decodeIfPresent([JSONValue].self, forKey: .responseOutput) ?? []
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
