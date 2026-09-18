import Foundation

enum AgentItemLegacyCodec {
    static func items(from messages: [AgentMessage]) -> [AgentItem] {
        var items: [AgentItem] = []
        for message in messages {
            switch message.role {
            case .system:
                if message.contextKind == .compactionSummary {
                    items.append(.compaction(CompactionItem(
                        summary: message.content ?? "",
                        summarizedItemCount: 0
                    )))
                } else {
                    items.append(.message(AgentMessageItem(
                        role: .system,
                        content: message.content
                    )))
                }
            case .user:
                items.append(.message(AgentMessageItem(
                    role: .user,
                    content: message.content,
                    imagePaths: message.imageAttachments?.map(\.path) ?? [],
                    contextKind: message.contextKind == .desktopObservation
                        ? .desktopObservation
                        : nil
                )))
            case .assistant:
                items.append(.message(AgentMessageItem(
                    role: .assistant,
                    content: message.content
                )))
                items.append(contentsOf: (message.toolCalls ?? []).map {
                    .toolCall(ToolCallItem(id: $0.id, name: $0.name, arguments: $0.arguments))
                })
            case .tool:
                items.append(.toolResult(ToolResultItem(
                    toolCallID: message.toolCallID ?? UUID().uuidString,
                    toolName: message.name ?? "unknown",
                    content: message.content ?? "",
                    isError: isErrorToolResult(message.content)
                )))
            }
        }
        return items
    }

    static func messages(from items: [AgentItem]) -> [AgentMessage] {
        var messages: [AgentMessage] = []
        for item in items {
            switch item {
            case .message(let item):
                switch item.contextKind {
                case .compactionSummary:
                    messages.append(.contextSummary(item.content ?? ""))
                case .desktopObservation:
                    messages.append(.desktopObservation(
                        item.content ?? "",
                        imagePaths: item.imagePaths
                    ))
                case nil:
                    switch item.role {
                    case .system:
                        messages.append(.system(item.content ?? ""))
                    case .user:
                        messages.append(.user(item.content ?? "", imagePaths: item.imagePaths))
                    case .assistant:
                        messages.append(.assistant(content: item.content))
                    }
                }
            case .toolCall(let item):
                let call = AgentToolCall(id: item.id, name: item.name, arguments: item.arguments)
                if messages.last?.role == .assistant {
                    var calls = messages[messages.count - 1].toolCalls ?? []
                    calls.append(call)
                    messages[messages.count - 1].toolCalls = calls
                } else {
                    messages.append(.assistant(content: nil, toolCalls: [call]))
                }
            case .toolResult(let item):
                messages.append(.tool(
                    call: AgentToolCall(
                        id: item.toolCallID,
                        name: item.toolName,
                        arguments: "{}"
                    ),
                    content: item.content
                ))
            case .compaction(let item):
                messages.append(.contextSummary(item.summary))
            case .handoff, .guardrail, .approval:
                continue
            }
        }
        return messages
    }

    private static func isErrorToolResult(_ content: String?) -> Bool {
        guard let content,
              let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool else { return false }
        return !ok
    }
}
