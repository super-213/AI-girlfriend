import Foundation

struct OpenAIResponsesStreamParser: AgentStreamParser {
    private var text = ""
    private var responseID: String?
    private var completed = false

    mutating func consume(line: String) throws -> [ModelStreamEvent] {
        guard let json = try AgentProviderWireSupport.jsonObject(from: line) else { return [] }
        if json["__done"] as? Bool == true {
            guard completed else {
                throw ModelProviderError.invalidResponse("Responses 流在 response.completed 前中断")
            }
            return []
        }
        let type = json["type"] as? String
        if type == "response.output_text.delta",
           let delta = json["delta"] as? String,
           !delta.isEmpty {
            text += delta
            return [.textDelta(delta)]
        }
        if type == "response.failed" || type == "response.incomplete" {
            let response = json["response"] as? [String: Any]
            let detailValue = response?["error"] ?? response?["incomplete_details"]
            let detail = detailValue.map { AgentProviderWireSupport.diagnosticDescription($0) }
                ?? "Responses 请求未完成"
            throw ModelProviderError.invalidResponse(detail)
        }
        guard type == "response.completed",
              let response = json["response"] as? [String: Any] else { return [] }
        completed = true
        responseID = response["id"] as? String
        let parsed = Self.response(response, fallbackText: text)
        text = parsed.content
        return [.completed(parsed)]
    }

    mutating func finish() throws -> [ModelStreamEvent] {
        guard completed else {
            throw ModelProviderError.invalidResponse("Responses 流在 response.completed 前中断")
        }
        return []
    }

    static func response(_ response: [String: Any], fallbackText: String = "") -> ModelResponse {
        var outputText = ""
        var calls: [ToolCallItem] = []
        for item in response["output"] as? [[String: Any]] ?? [] {
            switch item["type"] as? String {
            case "message":
                for content in item["content"] as? [[String: Any]] ?? []
                where content["type"] as? String == "output_text" {
                    outputText += content["text"] as? String ?? ""
                }
            case "function_call":
                guard let name = item["name"] as? String else { continue }
                calls.append(ToolCallItem(
                    id: item["call_id"] as? String
                        ?? item["id"] as? String
                        ?? "call-\(UUID().uuidString)",
                    name: name,
                    arguments: item["arguments"] as? String ?? "{}"
                ))
            default:
                continue
            }
        }
        return ModelResponse(
            id: response["id"] as? String,
            content: outputText.isEmpty ? fallbackText : outputText,
            toolCalls: calls,
            usage: AgentProviderWireSupport.usage(response["usage"] as? [String: Any])
        )
    }
}

struct OpenAIResponsesProviderCodec: AgentProviderCodec {
    let id = "openai-responses"
    let capabilities = ModelCapabilities(
        supportsTools: true,
        supportsParallelTools: true,
        supportsStructuredOutput: true,
        supportsImageInput: true,
        supportsServerManagedState: true,
        supportsPromptCaching: true,
        supportsResponsesAPI: true
    )

    func makeRequest(
        _ request: ModelRequest,
        configuration: AgentProviderConfiguration
    ) throws -> URLRequest {
        var instructions: [String] = []
        var input: [[String: Any]] = []
        for item in request.items {
            switch item {
            case .message(let message):
                if message.role == .system {
                    if let content = message.content { instructions.append(content) }
                    continue
                }
                var content: [[String: Any]] = []
                if let text = message.content, !text.isEmpty {
                    content.append([
                        "type": message.role == .assistant ? "output_text" : "input_text",
                        "text": text
                    ])
                }
                if message.role == .user {
                    content.append(contentsOf: message.imagePaths.map {
                        ["type": "input_image", "image_url": Self.imageDataURL(path: $0)]
                    })
                }
                input.append([
                    "type": "message",
                    "role": message.role.rawValue,
                    "content": content
                ])
            case .toolCall(let call):
                input.append([
                    "type": "function_call",
                    "call_id": call.id,
                    "name": call.name,
                    "arguments": call.arguments
                ])
            case .toolResult(let result):
                input.append([
                    "type": "function_call_output",
                    "call_id": result.toolCallID,
                    "output": result.content
                ])
            case .compaction(let compaction):
                input.append([
                    "type": "message",
                    "role": "developer",
                    "content": [["type": "input_text", "text": compaction.summary]]
                ])
            case .handoff, .guardrail, .approval:
                continue
            }
        }

        var payload: [String: Any] = [
            "model": AgentProviderWireSupport.modelID(request, fallback: configuration.model),
            "input": input,
            "stream": true,
            "parallel_tool_calls": true,
            "store": false
        ]
        if !instructions.isEmpty { payload["instructions"] = instructions.joined(separator: "\n\n") }
        if !request.tools.isEmpty {
            payload["tools"] = request.tools.map(AgentProviderWireSupport.strictToolJSON)
            payload["tool_choice"] = "auto"
        }
        if let output = request.outputSchema {
            var format: [String: Any] = [
                "type": "json_schema",
                "name": output.name,
                "schema": output.schema.foundationValue,
                "strict": output.strict
            ]
            if let description = output.description { format["description"] = description }
            payload["text"] = ["format": format]
        }
        return try AgentProviderWireSupport.request(
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            payload: payload
        )
    }

    func makeParser() -> any AgentStreamParser { OpenAIResponsesStreamParser() }

    private static func imageDataURL(path: String) -> String {
        let attachment = AgentImageAttachment(path: path)
        guard let base64 = attachment.base64Payload() else { return "" }
        return "data:\(attachment.mimeType);base64,\(base64)"
    }
}

struct OpenAIResponsesProvider: AgentModelProvider {
    private let base: HTTPAgentModelProvider
    var id: String { base.id }
    var capabilities: ModelCapabilities { base.capabilities }

    init(
        configuration: AgentProviderConfiguration,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport.shared
    ) {
        base = HTTPAgentModelProvider(
            configuration: configuration,
            codec: OpenAIResponsesProviderCodec(),
            transport: transport
        )
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        base.streamResponse(request: request)
    }
    func cancel(runID: UUID) async { await base.cancel(runID: runID) }
}
