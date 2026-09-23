import Foundation

private struct StreamingToolPart: Sendable {
    var id = ""
    var name = ""
    var arguments = ""
}

struct ChatCompletionStreamParser: AgentStreamParser {
    private var responseID: String?
    private var text = ""
    private var toolParts: [Int: StreamingToolPart] = [:]
    private var usage: AgentUsage?
    private var completed = false

    mutating func consume(line: String) throws -> [ModelStreamEvent] {
        guard let json = try AgentProviderWireSupport.jsonObject(from: line) else { return [] }
        if json["__done"] as? Bool == true { return completeIfNeeded() }
        if let id = json["id"] as? String { responseID = id }
        if let parsed = AgentProviderWireSupport.usage(json["usage"] as? [String: Any]) {
            usage = parsed
        }
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return [] }
        let delta = (choice["delta"] as? [String: Any])
            ?? (choice["message"] as? [String: Any])
            ?? [:]
        var events: [ModelStreamEvent] = []
        if let content = delta["content"] as? String, !content.isEmpty {
            text += content
            events.append(.textDelta(content))
        }
        if let calls = delta["tool_calls"] as? [[String: Any]] {
            for (fallbackIndex, call) in calls.enumerated() {
                let index = (call["index"] as? NSNumber)?.intValue ?? fallbackIndex
                var part = toolParts[index] ?? StreamingToolPart()
                if let id = call["id"] as? String { part.id += id }
                if let function = call["function"] as? [String: Any] {
                    if let name = function["name"] as? String { part.name += name }
                    if let arguments = function["arguments"] as? String {
                        part.arguments += arguments
                    } else if let arguments = function["arguments"],
                              JSONSerialization.isValidJSONObject(arguments),
                              let data = try? JSONSerialization.data(withJSONObject: arguments) {
                        part.arguments += String(data: data, encoding: .utf8) ?? "{}"
                    }
                }
                toolParts[index] = part
            }
        }
        if let finishReason = choice["finish_reason"], !(finishReason is NSNull) {
            events += completeIfNeeded()
        }
        return events
    }

    mutating func finish() throws -> [ModelStreamEvent] {
        guard completed else {
            throw ModelProviderError.invalidResponse("Chat Completions 流在完成事件前中断")
        }
        return []
    }

    private mutating func completeIfNeeded() -> [ModelStreamEvent] {
        guard !completed else { return [] }
        completed = true
        let calls: [ToolCallItem] = toolParts
            .sorted(by: { $0.key < $1.key })
            .compactMap { element -> ToolCallItem? in
            let part = element.value
            guard !part.name.isEmpty else { return nil }
            return ToolCallItem(
                id: part.id.isEmpty ? "call-\(UUID().uuidString)" : part.id,
                name: part.name,
                arguments: part.arguments.isEmpty ? "{}" : part.arguments
            )
        }
        return [.completed(ModelResponse(
            id: responseID,
            content: text,
            toolCalls: calls,
            usage: usage
        ))]
    }
}

struct ChatCompletionProviderCodec: AgentProviderCodec {
    enum Flavor: Sendable, Equatable { case openAICompatible, zhipu }

    let flavor: Flavor
    var id: String { flavor == .zhipu ? "zhipu-chat" : "openai-compatible-chat" }
    var capabilities: ModelCapabilities {
        ModelCapabilities(
            supportsTools: true,
            supportsParallelTools: flavor == .openAICompatible,
            supportsStructuredOutput: flavor == .openAICompatible,
            supportsImageInput: true,
            supportsServerManagedState: false,
            supportsPromptCaching: flavor == .openAICompatible,
            supportsResponsesAPI: false
        )
    }

    func makeRequest(
        _ request: ModelRequest,
        configuration: AgentProviderConfiguration
    ) throws -> URLRequest {
        var payload: [String: Any] = [
            "model": AgentProviderWireSupport.modelID(request, fallback: configuration.model),
            "messages": AgentProviderWireSupport.chatMessages(request.items),
            "stream": true
        ]
        if flavor == .openAICompatible {
            payload["stream_options"] = ["include_usage": true]
        } else {
            payload["temperature"] = 0.7
            payload["top_p"] = 0.7
        }
        if !request.tools.isEmpty {
            payload["tools"] = request.tools.map(AgentProviderWireSupport.toolJSON)
            payload["tool_choice"] = "auto"
            if capabilities.supportsParallelTools { payload["parallel_tool_calls"] = true }
        }
        if let output = request.outputSchema {
            var jsonSchema: [String: Any] = [
                "name": output.name,
                "schema": output.schema.foundationValue,
                "strict": output.strict
            ]
            if let description = output.description { jsonSchema["description"] = description }
            payload["response_format"] = [
                "type": "json_schema",
                "json_schema": jsonSchema
            ]
        }
        return try AgentProviderWireSupport.request(
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            payload: payload
        )
    }

    func makeParser() -> any AgentStreamParser { ChatCompletionStreamParser() }
}
