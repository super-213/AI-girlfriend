import Foundation

public struct ModelRequest: Sendable {
    public let runID: UUID
    public let agentID: String
    public let model: AgentModelConfiguration
    public let items: [AgentItem]
    public let tools: [ToolDefinition]
    public let outputSchema: AgentOutputSchema?
    public let purpose: AgentRequestPurpose

    public init(
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

public struct ModelResponse: Codable, Equatable, Sendable {
    public let id: String?
    public let content: String
    public let toolCalls: [ToolCallItem]
    public let usage: AgentUsage?
    public let responseOutput: [JSONValue]

    public init(
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        toolCalls = try container.decode([ToolCallItem].self, forKey: .toolCalls)
        usage = try container.decodeIfPresent(AgentUsage.self, forKey: .usage)
        responseOutput = try container.decodeIfPresent([JSONValue].self, forKey: .responseOutput) ?? []
    }
}

public enum ModelStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case completed(ModelResponse)
}

public protocol AgentModelProvider: Sendable {
    var id: String { get }
    var capabilities: ModelCapabilities { get }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error>
    func cancel(runID: UUID) async
}

public extension AgentModelProvider {
    func cancel(runID: UUID) async {}
}
