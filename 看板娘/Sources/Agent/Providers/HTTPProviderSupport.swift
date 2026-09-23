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
                        throw ModelProviderError.transport(
                            await Self.httpFailure(http, bytes: bytes, request: request)
                        )
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AgentError.cancelled)
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: AgentError.cancelled)
                    } else if error is ModelProviderError {
                        continuation.finish(throwing: error)
                    } else {
                        continuation.finish(throwing: ModelProviderError.transport(
                            Self.networkFailure(error, request: request)
                        ))
                    }
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

    private static func httpFailure(
        _ response: HTTPURLResponse,
        bytes: URLSession.AsyncBytes,
        request: URLRequest
    ) async -> String {
        let maximumBodyBytes = 64 * 1024
        var body = Data()
        var truncated = false
        var bodyReadError: Error?
        do {
            for try await byte in bytes {
                if body.count < maximumBodyBytes {
                    body.append(byte)
                } else {
                    truncated = true
                    break
                }
            }
        } catch {
            bodyReadError = error
        }
        var details = ["HTTP \(response.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: response.statusCode))",
                       "请求：\(request.httpMethod ?? "GET") \(endpointDescription(request.url))"]
        for name in ["x-request-id", "request-id", "x-correlation-id", "retry-after",
                     "x-ratelimit-limit-requests", "x-ratelimit-remaining-requests",
                     "x-ratelimit-reset-requests", "x-ratelimit-limit-tokens",
                     "x-ratelimit-remaining-tokens", "x-ratelimit-reset-tokens"] {
            if let value = response.value(forHTTPHeaderField: name) {
                details.append("\(name)：\(value)")
            }
        }
        let responseBody = String(decoding: body, as: UTF8.self)
        if !responseBody.isEmpty {
            details.append("响应体：\(responseBody)\(truncated ? "\n（响应体超过 64 KiB，已截断）" : "")")
        }
        if let bodyReadError {
            let failure = bodyReadError as NSError
            details.append("读取响应体失败：\(failure.domain) (\(failure.code))：\(failure.localizedDescription)")
        }
        return redact(details.joined(separator: "\n"), request: request)
    }

    private static func networkFailure(_ error: Error, request: URLRequest) -> String {
        var details = ["请求：\(request.httpMethod ?? "GET") \(endpointDescription(request.url))"]
        var current: NSError? = error as NSError
        for _ in 0..<4 {
            guard let problem = current else { break }
            details.append("\(problem.domain) (\(problem.code))：\(problem.localizedDescription)")
            current = problem.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return redact(details.joined(separator: "\n"), request: request)
    }

    private static func endpointDescription(_ url: URL?) -> String {
        guard let url else { return "未知地址" }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(url.scheme ?? "?")://\(url.host ?? "?")\(port)\(url.path)"
    }

    private static func redact(_ value: String, request: URLRequest) -> String {
        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let secret = authorization.hasPrefix("Bearer ") ? String(authorization.dropFirst(7)) : ""
        let querySecrets = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return name.contains("key") || name.contains("token") || name.contains("secret")
            }
            .compactMap(\.value) ?? []
        return SensitiveDataRedactor.redact(value, secrets: [secret] + querySecrets)
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
                    let reportedError = self.redactedError(error)
                    let detail = reportedError.localizedDescription
                    print("模型请求失败 [\(self.id), runID=\(request.runID)]：\(detail)")
                    continuation.finish(throwing: reportedError)
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

    private func redactedError(_ error: Error) -> Error {
        guard let providerError = error as? ModelProviderError else { return error }
        let secrets = [configuration.apiKey].compactMap { $0 }
        switch providerError {
        case .unavailable(let detail):
            return ModelProviderError.unavailable(SensitiveDataRedactor.redact(detail, secrets: secrets))
        case .unsupportedCapability(let detail):
            return ModelProviderError.unsupportedCapability(SensitiveDataRedactor.redact(detail, secrets: secrets))
        case .invalidResponse(let detail):
            return ModelProviderError.invalidResponse(SensitiveDataRedactor.redact(detail, secrets: secrets))
        case .transport(let detail):
            return ModelProviderError.transport(SensitiveDataRedactor.redact(detail, secrets: secrets))
        }
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
                                usage: response.usage,
                                responseOutput: response.responseOutput
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
            "strict": supportsStrictFunctionSchema(tool.parameters)
        ]
    }

    private static func supportsStrictFunctionSchema(_ schema: JSONValue) -> Bool {
        guard case .object(let root) = schema,
              root["type"] == .string("object") else { return false }
        return strictObjectConstraintsHold(schema)
    }

    private static func strictObjectConstraintsHold(_ schema: JSONValue) -> Bool {
        switch schema {
        case .array(let values):
            return values.allSatisfy(strictObjectConstraintsHold)
        case .object(let object):
            let isObject: Bool
            switch object["type"] {
            case .string("object"):
                isObject = true
            case .array(let types):
                isObject = types.contains(.string("object"))
            default:
                isObject = object["properties"] != nil
            }
            if isObject {
                guard object["additionalProperties"] == .bool(false) else { return false }
                let properties: [String: JSONValue]
                if case .object(let value)? = object["properties"] {
                    properties = value
                } else if object["properties"] == nil {
                    properties = [:]
                } else {
                    return false
                }
                let required: Set<String>
                if case .array(let values)? = object["required"] {
                    let names = values.compactMap { value -> String? in
                        guard case .string(let name) = value else { return nil }
                        return name
                    }
                    guard names.count == values.count else { return false }
                    required = Set(names)
                } else {
                    required = []
                }
                guard required == Set(properties.keys) else { return false }
            }
            return object.values.allSatisfy(strictObjectConstraintsHold)
        case .string, .number, .bool, .null:
            return true
        }
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
            let detail = diagnosticDescription(error)
            throw ModelProviderError.transport("Provider 返回错误：\(detail)")
        }
        if let error = json["error"] as? String, !error.isEmpty {
            throw ModelProviderError.transport(SensitiveDataRedactor.redact(error))
        }
        return json
    }

    static func diagnosticDescription(_ value: Any?) -> String {
        guard let value else { return "未知错误" }
        if let text = value as? String { return SensitiveDataRedactor.redact(text) }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return SensitiveDataRedactor.redact(String(describing: value))
        }
        return SensitiveDataRedactor.redact(value)
    }
}
