import Foundation

struct AgentProviderConfiguration: Sendable, Equatable {
    let id: String
    let endpoint: URL
    let model: String
    let apiKey: String?

    init(id: String, endpoint: URL, model: String, apiKey: String? = nil) {
        self.id = id
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }
}

protocol AgentHTTPTransport: Sendable {
    func streamLines(
        request: URLRequest,
        runID: UUID
    ) -> AsyncThrowingStream<String, Error>
    func cancel(runID: UUID) async
}

final class URLSessionAgentHTTPTransport: AgentHTTPTransport, @unchecked Sendable {
    static let shared = URLSessionAgentHTTPTransport()

    private let session: URLSession
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streamLines(
        request: URLRequest,
        runID: UUID
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                defer { self.removeTask(runID: runID) }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ModelProviderError.invalidResponse("缺少 HTTP 响应")
                    }
                    guard 200..<300 ~= http.statusCode else {
                        throw ModelProviderError.transport("HTTP \(http.statusCode)")
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AgentError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            register(task, runID: runID)
            continuation.onTermination = { @Sendable _ in
                Task { await self.cancel(runID: runID) }
            }
        }
    }

    func cancel(runID: UUID) async {
        let task = lock.withLock { tasks.removeValue(forKey: runID) }
        task?.cancel()
    }

    private func register(_ task: Task<Void, Never>, runID: UUID) {
        let previous = lock.withLock { tasks.updateValue(task, forKey: runID) }
        previous?.cancel()
    }

    private func removeTask(runID: UUID) {
        _ = lock.withLock { tasks.removeValue(forKey: runID) }
    }
}

protocol AgentStreamParser: Sendable {
    mutating func consume(line: String) throws -> [ModelStreamEvent]
    mutating func finish() throws -> [ModelStreamEvent]
}

protocol AgentProviderCodec: Sendable {
    var id: String { get }
    var capabilities: ModelCapabilities { get }
    func makeRequest(
        _ request: ModelRequest,
        configuration: AgentProviderConfiguration
    ) throws -> URLRequest
    func makeParser() -> any AgentStreamParser
}

final class HTTPAgentModelProvider: AgentModelProvider, @unchecked Sendable {
    let id: String
    let capabilities: ModelCapabilities

    private let configuration: AgentProviderConfiguration
    private let codec: any AgentProviderCodec
    private let transport: any AgentHTTPTransport

    init(
        configuration: AgentProviderConfiguration,
        codec: any AgentProviderCodec,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport.shared
    ) {
        self.configuration = configuration
        self.codec = codec
        self.transport = transport
        id = codec.id
        capabilities = codec.capabilities
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        let urlRequest: URLRequest
        do {
            urlRequest = try codec.makeRequest(request, configuration: configuration)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let lines = transport.streamLines(request: urlRequest, runID: request.runID)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = codec.makeParser()
                do {
                    for try await line in lines {
                        for event in try parser.consume(line: line) {
                            continuation.yield(event)
                        }
                    }
                    for event in try parser.finish() { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await self.transport.cancel(runID: request.runID) }
            }
        }
    }

    func cancel(runID: UUID) async {
        await transport.cancel(runID: runID)
    }
}

/// Provider middleware for app-specific tool-name repair without coupling wire adapters to UI state.
final class ToolCallNormalizingModelProvider: AgentModelProvider, @unchecked Sendable {
    let id: String
    let capabilities: ModelCapabilities

    private let base: any AgentModelProvider
    private let normalize: @MainActor @Sendable (ToolCallItem) -> ToolCallItem

    @MainActor
    init(
        base: any AgentModelProvider,
        normalize: @escaping @MainActor @Sendable (ToolCallItem) -> ToolCallItem
    ) {
        self.base = base
        self.normalize = normalize
        id = base.id
        capabilities = base.capabilities
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in base.streamResponse(request: request) {
                        switch event {
                        case .textDelta:
                            continuation.yield(event)
                        case .completed(let response):
                            var calls: [ToolCallItem] = []
                            for call in response.toolCalls {
                                calls.append(await normalize(call))
                            }
                            continuation.yield(.completed(ModelResponse(
                                id: response.id,
                                content: response.content,
                                toolCalls: calls,
                                usage: response.usage
                            )))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await self.base.cancel(runID: request.runID) }
            }
        }
    }

    func cancel(runID: UUID) async {
        await base.cancel(runID: runID)
    }
}

enum AgentProviderWireSupport {
    static func request(
        endpoint: URL,
        apiKey: String?,
        payload: [String: Any]
    ) throws -> URLRequest {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw ModelProviderError.invalidResponse("Provider 请求不是有效 JSON")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func modelID(_ request: ModelRequest, fallback: String) -> String {
        request.model.modelID == "default" ? fallback : request.model.modelID
    }

    static func toolJSON(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters.foundationValue
            ]
        ]
    }

    static func strictToolJSON(_ tool: ToolDefinition) -> [String: Any] {
        [
            "type": "function",
            "name": tool.name,
            "description": tool.description,
            "parameters": tool.parameters.foundationValue,
            "strict": true
        ]
    }

    static func chatMessages(_ items: [AgentItem], ollama: Bool = false) -> [[String: Any]] {
        AgentItemLegacyCodec.messages(from: items).map {
            ollama ? $0.ollamaJSONObject() : $0.jsonObject()
        }
    }

    static func usage(_ object: [String: Any]?) -> AgentUsage? {
        guard let object else { return nil }
        let input = (object["input_tokens"] as? NSNumber)?.intValue
            ?? (object["prompt_tokens"] as? NSNumber)?.intValue
            ?? (object["prompt_eval_count"] as? NSNumber)?.intValue
            ?? 0
        let output = (object["output_tokens"] as? NSNumber)?.intValue
            ?? (object["completion_tokens"] as? NSNumber)?.intValue
            ?? (object["eval_count"] as? NSNumber)?.intValue
            ?? 0
        let total = (object["total_tokens"] as? NSNumber)?.intValue ?? input + output
        guard input > 0 || output > 0 || total > 0 else { return nil }
        return AgentUsage(inputTokens: input, outputTokens: output, totalTokens: total)
    }

    static func jsonObject(from line: String) throws -> [String: Any]? {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix(":") { return nil }
        if value.hasPrefix("event:")
            || value.hasPrefix("id:")
            || value.hasPrefix("retry:") {
            return nil
        }
        if value.hasPrefix("data:") {
            value = String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        guard value != "[DONE]" else { return ["__done": true] }
        guard let data = value.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelProviderError.invalidResponse("无法解析 Provider 流事件")
        }
        if let error = json["error"] as? [String: Any] {
            throw ModelProviderError.transport(error["message"] as? String ?? "Provider 返回错误")
        }
        if let error = json["error"] as? String, !error.isEmpty {
            throw ModelProviderError.transport(error)
        }
        return json
    }
}
