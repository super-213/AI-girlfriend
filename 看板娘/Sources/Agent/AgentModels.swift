//
//  AgentModels.swift
//  看板娘
//
//  Provider-neutral messages and tool-call models used by the agent runtime.
//

import Foundation

enum AgentMessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
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

struct AgentMessage: Codable, Equatable {
    let role: AgentMessageRole
    var content: String?
    var toolCalls: [AgentToolCall]?
    var toolCallID: String?
    var name: String?

    static func system(_ content: String) -> AgentMessage {
        AgentMessage(role: .system, content: content)
    }

    static func user(_ content: String) -> AgentMessage {
        AgentMessage(role: .user, content: content)
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

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = ["role": role.rawValue]
        if let content {
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
}

struct AgentToolExecutionResult: Equatable {
    let content: String
    let isError: Bool

    static func success(_ content: String) -> AgentToolExecutionResult {
        AgentToolExecutionResult(content: content, isError: false)
    }

    static func failure(_ content: String) -> AgentToolExecutionResult {
        AgentToolExecutionResult(content: content, isError: true)
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
