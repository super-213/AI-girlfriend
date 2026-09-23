import Foundation

struct OllamaStreamParser: AgentStreamParser {
    private var text = ""
    private var toolCalls: [ToolCallItem] = []
    private var usage: AgentUsage?
    private var completed = false

    mutating func consume(line: String) throws -> [ModelStreamEvent] {
        guard let json = try AgentProviderWireSupport.jsonObject(from: line) else { return [] }
        if let parsed = AgentProviderWireSupport.usage(json) { usage = parsed }
        var events: [ModelStreamEvent] = []
        if let message = json["message"] as? [String: Any] {
            if let content = message["content"] as? String, !content.isEmpty {
                text += content
                events.append(.textDelta(content))
            }
            if let calls = message["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    guard let function = call["function"] as? [String: Any],
                          let name = function["name"] as? String else { continue }
                    let arguments: String
                    if let value = function["arguments"] as? String {
                        arguments = value
                    } else if let value = function["arguments"],
                              JSONSerialization.isValidJSONObject(value),
                              let data = try? JSONSerialization.data(withJSONObject: value) {
                        arguments = String(data: data, encoding: .utf8) ?? "{}"
                    } else {
                        arguments = "{}"
                    }
                    toolCalls.append(ToolCallItem(
                        id: call["id"] as? String ?? "ollama-\(UUID().uuidString)",
                        name: name,
                        arguments: arguments
                    ))
                }
            }
        }
        if json["done"] as? Bool == true { events += completeIfNeeded() }
        return events
    }

    mutating func finish() throws -> [ModelStreamEvent] {
        guard completed else {
            throw ModelProviderError.invalidResponse("Ollama 流在 done=true 前中断")
        }
        return []
    }

    private mutating func completeIfNeeded() -> [ModelStreamEvent] {
        guard !completed else { return [] }
        completed = true
        return [.completed(ModelResponse(
            content: text,
            toolCalls: toolCalls,
            usage: usage
        ))]
    }
}

struct OllamaProviderCodec: AgentProviderCodec {
    let id = "ollama-chat"
    let capabilities = ModelCapabilities(
        supportsTools: true,
        supportsParallelTools: false,
        supportsStructuredOutput: true,
        supportsImageInput: true,
        supportsServerManagedState: false,
        supportsPromptCaching: false,
        supportsResponsesAPI: false
    )

    func makeRequest(
        _ request: ModelRequest,
        configuration: AgentProviderConfiguration
    ) throws -> URLRequest {
        var payload: [String: Any] = [
            "model": AgentProviderWireSupport.modelID(request, fallback: configuration.model),
            "messages": AgentProviderWireSupport.chatMessages(request.items, ollama: true),
            "stream": true,
            "options": ["temperature": 0.7, "top_p": 0.7]
        ]
        if !request.tools.isEmpty {
            payload["tools"] = request.tools.map(AgentProviderWireSupport.toolJSON)
        }
        if let output = request.outputSchema {
            payload["format"] = output.schema.foundationValue
        }
        return try AgentProviderWireSupport.request(
            endpoint: configuration.endpoint,
            apiKey: nil,
            payload: payload
        )
    }

    func makeParser() -> any AgentStreamParser { OllamaStreamParser() }
}

public struct OllamaChatProvider: AgentModelProvider {
    private let base: HTTPAgentModelProvider
    public var id: String { base.id }
    public var capabilities: ModelCapabilities { base.capabilities }

    public init(
        configuration: AgentProviderConfiguration,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport.shared
    ) {
        base = HTTPAgentModelProvider(
            configuration: configuration,
            codec: OllamaProviderCodec(),
            transport: transport
        )
    }

    public func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        base.streamResponse(request: request)
    }
    public func cancel(runID: UUID) async { await base.cancel(runID: runID) }
}
