//
//  AgentModels.swift
//  看板娘
//
//  Provider-neutral messages and tool-call models used by the agent runtime.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum AgentMessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

enum AgentMessageContextKind: String, Codable {
    case compactionSummary
    case desktopObservation
}

enum AgentRequestPurpose: String {
    case conversation
    case contextCompaction
}

struct AgentToolCall: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let arguments: String

    func decodedArguments() throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentRuntimeError.invalidToolArguments(name)
        }
        return object
    }
}

struct AgentImageAttachment: Codable, Equatable, Identifiable {
    let id: UUID
    let path: String

    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
    }

    var mimeType: String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        default: return "image/png"
        }
    }

    func base64Payload() -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        if data.count <= 10 * 1_024 * 1_024 {
            return data.base64EncodedString()
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: 0.84
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (mutableData as Data).base64EncodedString()
    }
}

struct AgentMessage: Codable, Equatable {
    let role: AgentMessageRole
    var content: String?
    var toolCalls: [AgentToolCall]?
    var toolCallID: String?
    var name: String?
    var contextKind: AgentMessageContextKind?
    var imageAttachments: [AgentImageAttachment]?

    static func system(_ content: String) -> AgentMessage {
        AgentMessage(role: .system, content: content)
    }

    static func user(_ content: String, imagePaths: [String] = []) -> AgentMessage {
        AgentMessage(
            role: .user,
            content: content,
            imageAttachments: imagePaths.isEmpty ? nil : imagePaths.map { AgentImageAttachment(path: $0) }
        )
    }

    static func desktopObservation(_ content: String, imagePaths: [String]) -> AgentMessage {
        AgentMessage(
            role: .user,
            content: content,
            contextKind: .desktopObservation,
            imageAttachments: imagePaths.isEmpty ? nil : imagePaths.map { AgentImageAttachment(path: $0) }
        )
    }

    static func assistant(content: String?, toolCalls: [AgentToolCall] = []) -> AgentMessage {
        AgentMessage(
            role: .assistant,
            content: content,
            toolCalls: toolCalls.isEmpty ? nil : toolCalls
        )
    }

    static func tool(call: AgentToolCall, content: String) -> AgentMessage {
        AgentMessage(
            role: .tool,
            content: content,
            toolCallID: call.id,
            name: call.name
        )
    }

    static func contextSummary(_ content: String) -> AgentMessage {
        AgentMessage(
            role: .system,
            content: content,
            contextKind: .compactionSummary
        )
    }

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = ["role": role.rawValue]
        if role == .user, let imageAttachments, !imageAttachments.isEmpty {
            var parts: [[String: Any]] = []
            if let content, !content.isEmpty {
                parts.append(["type": "text", "text": content])
            }
            for image in imageAttachments {
                guard let payload = image.base64Payload() else { continue }
                parts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(image.mimeType);base64,\(payload)"]
                ])
            }
            object["content"] = parts
        } else if let content {
            object["content"] = content
        } else if role == .assistant {
            object["content"] = NSNull()
        }
        if let toolCallID { object["tool_call_id"] = toolCallID }
        if let name { object["name"] = name }
        if let toolCalls, !toolCalls.isEmpty {
            object["tool_calls"] = toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments
                    ]
                ]
            }
        }
        return object
    }

    func ollamaJSONObject() -> [String: Any] {
        var object: [String: Any] = ["role": role.rawValue]
        if let content { object["content"] = content }
        if role == .user, let imageAttachments, !imageAttachments.isEmpty {
            object["images"] = imageAttachments.compactMap { $0.base64Payload() }
        }
        if let toolCalls, !toolCalls.isEmpty {
            object["tool_calls"] = toolCalls.map { call in
                let arguments = (try? call.decodedArguments()) ?? [:]
                return [
                    "type": "function",
                    "function": ["name": call.name, "arguments": arguments]
                ] as [String: Any]
            }
        }
        return object
    }
}

struct AgentToolDefinition {
    let name: String
    let description: String
    let parameters: [String: Any]

    func jsonObject() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }
}

struct AgentModelResponse: Equatable {
    let content: String
    let toolCalls: [AgentToolCall]
    let usage: AgentTokenUsage?

    init(
        content: String,
        toolCalls: [AgentToolCall],
        usage: AgentTokenUsage? = nil
    ) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

struct AgentTokenUsage: Equatable {
    let promptTokens: Int
    let completionTokens: Int?
    let totalTokens: Int?
    let cachedTokens: Int?
    let cacheCreationTokens: Int?
    let cacheWriteTokens: Int?

    var cacheHitRatio: Double? {
        guard promptTokens > 0, let cachedTokens else { return nil }
        return Double(cachedTokens) / Double(promptTokens)
    }

    /// Parses OpenAI-compatible/Zhipu usage objects and Ollama's final
    /// top-level evaluation counters without treating missing cache data as 0.
    init?(responseJSONObject json: [String: Any]) {
        let usage = json["usage"] as? [String: Any] ?? json
        let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
        let inputDetails = usage["input_tokens_details"] as? [String: Any]

        guard let promptTokens = Self.integer(
            usage["prompt_tokens"]
                ?? usage["input_tokens"]
                ?? usage["prompt_eval_count"]
        ) else { return nil }

        self.promptTokens = promptTokens
        completionTokens = Self.integer(
            usage["completion_tokens"]
                ?? usage["output_tokens"]
                ?? usage["eval_count"]
        )
        totalTokens = Self.integer(usage["total_tokens"])
        cachedTokens = Self.integer(
            promptDetails?["cached_tokens"]
                ?? inputDetails?["cached_tokens"]
                ?? usage["cached_tokens"]
        )
        cacheCreationTokens = Self.integer(
            promptDetails?["cache_creation_input_tokens"]
                ?? inputDetails?["cache_creation_input_tokens"]
                ?? usage["cache_creation_input_tokens"]
        )
        cacheWriteTokens = Self.integer(
            promptDetails?["cache_write_tokens"]
                ?? inputDetails?["cache_write_tokens"]
                ?? usage["cache_write_tokens"]
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}

struct AgentCacheMetrics: Codable, Equatable {
    var requestCount = 0
    var measuredRequestCount = 0
    var promptTokens = 0
    var measuredPromptTokens = 0
    var cachedTokens = 0
    var cacheCreationTokens = 0
    var cacheWriteTokens = 0
    var lastUpdatedAt = Date.distantPast

    var cacheHitRatio: Double? {
        guard measuredPromptTokens > 0 else { return nil }
        return Double(cachedTokens) / Double(measuredPromptTokens)
    }
}

enum AgentCacheMetricsStore {
    static let storageKey = "agent.cacheMetrics.v1"

    static func record(
        _ usage: AgentTokenUsage,
        provider: String,
        model: String,
        defaults: UserDefaults = .standard
    ) -> AgentCacheMetrics {
        let key = metricKey(provider: provider, model: model)
        var allMetrics = load(defaults: defaults)
        var metrics = allMetrics[key] ?? AgentCacheMetrics()
        metrics.requestCount += 1
        metrics.promptTokens += usage.promptTokens
        if let cachedTokens = usage.cachedTokens {
            metrics.measuredRequestCount += 1
            metrics.measuredPromptTokens += usage.promptTokens
            metrics.cachedTokens += cachedTokens
        }
        metrics.cacheCreationTokens += usage.cacheCreationTokens ?? 0
        metrics.cacheWriteTokens += usage.cacheWriteTokens ?? 0
        metrics.lastUpdatedAt = .now
        allMetrics[key] = metrics

        if let data = try? JSONEncoder().encode(allMetrics) {
            defaults.set(data, forKey: storageKey)
        }
        return metrics
    }

    static func load(defaults: UserDefaults = .standard) -> [String: AgentCacheMetrics] {
        guard let data = defaults.data(forKey: storageKey),
              let metrics = try? JSONDecoder().decode([String: AgentCacheMetrics].self, from: data) else {
            return [:]
        }
        return metrics
    }

    static func metricKey(provider: String, model: String) -> String {
        "\(provider.lowercased())|\(model)"
    }
}

struct AgentToolExecutionResult: Equatable {
    let content: String
    let isError: Bool
    let imagePaths: [String]

    static func success(_ content: String, imagePaths: [String] = []) -> AgentToolExecutionResult {
        AgentToolExecutionResult(content: content, isError: false, imagePaths: imagePaths)
    }

    static func failure(_ content: String, imagePaths: [String] = []) -> AgentToolExecutionResult {
        AgentToolExecutionResult(content: content, isError: true, imagePaths: imagePaths)
    }

    var modelContent: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["ok": !isError, "result": content],
            options: [.sortedKeys]
        ) else { return content }
        return String(data: data, encoding: .utf8) ?? content
    }
}

enum AgentRuntimeError: LocalizedError {
    case busy
    case invalidToolArguments(String)
    case iterationLimit
    case toolUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .busy:
            return "Agent 正在处理上一项任务"
        case .invalidToolArguments(let name):
            return "工具 \(name) 的参数不是有效 JSON 对象"
        case .iterationLimit:
            return "Agent 已达到最大工具调用轮数"
        case .toolUnavailable(let name):
            return "模型请求了未注册的工具：\(name)"
        }
    }
}
