import Foundation

enum AgentItemRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

struct AgentMessageItem: Codable, Equatable, Sendable {
    let id: UUID
    let role: AgentItemRole
    let content: String?
    let imagePaths: [String]

    init(id: UUID = UUID(), role: AgentItemRole, content: String?, imagePaths: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePaths = imagePaths
    }
}

struct ToolCallItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let arguments: String
}

struct ToolResultItem: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let toolCallID: String
    let toolName: String
    let content: String
    let isError: Bool
    let imagePaths: [String]

    init(
        id: UUID = UUID(),
        toolCallID: String,
        toolName: String,
        content: String,
        isError: Bool,
        imagePaths: [String] = []
    ) {
        self.id = id
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.content = content
        self.isError = isError
        self.imagePaths = imagePaths
    }
}

struct HandoffItem: Codable, Equatable, Sendable {
    let sourceAgentID: String
    let targetAgentID: String
    let reason: String
}

struct GuardrailItem: Codable, Equatable, Sendable {
    let result: GuardrailResult
}

struct ApprovalItem: Codable, Equatable, Sendable {
    let interruptionID: UUID
    let decision: ApprovalDecision?
}

struct CompactionItem: Codable, Equatable, Sendable {
    let summary: String
    let summarizedItemCount: Int
}

enum AgentItem: Codable, Equatable, Sendable {
    case message(AgentMessageItem)
    case toolCall(ToolCallItem)
    case toolResult(ToolResultItem)
    case handoff(HandoffItem)
    case guardrail(GuardrailItem)
    case approval(ApprovalItem)
    case compaction(CompactionItem)
}
