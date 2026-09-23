import Foundation

public enum AgentItemRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public enum AgentItemContextKind: String, Codable, Sendable {
    case compactionSummary
    case desktopObservation
}

public struct AgentMessageItem: Codable, Equatable, Sendable {
    public let id: UUID
    public let role: AgentItemRole
    public let content: String?
    public let imagePaths: [String]
    public let contextKind: AgentItemContextKind?

    public init(
        id: UUID = UUID(),
        role: AgentItemRole,
        content: String?,
        imagePaths: [String] = [],
        contextKind: AgentItemContextKind? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imagePaths = imagePaths
        self.contextKind = contextKind
    }
}

public struct ToolCallItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolResultItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let toolCallID: String
    public let toolName: String
    public let content: String
    public let isError: Bool
    public let imagePaths: [String]

    public init(
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

public struct HandoffItem: Codable, Equatable, Sendable {
    public let sourceAgentID: String
    public let targetAgentID: String
    public let reason: String
    public let metadata: JSONValue?

    public init(
        sourceAgentID: String,
        targetAgentID: String,
        reason: String,
        metadata: JSONValue? = nil
    ) {
        self.sourceAgentID = sourceAgentID
        self.targetAgentID = targetAgentID
        self.reason = reason
        self.metadata = metadata
    }
}

public struct GuardrailItem: Codable, Equatable, Sendable {
    public let result: GuardrailResult
}

public struct ApprovalItem: Codable, Equatable, Sendable {
    public let interruptionID: UUID
    public let decision: ApprovalDecision?
}

public struct CompactionItem: Codable, Equatable, Sendable {
    public let summary: String
    public let summarizedItemCount: Int
}

public enum AgentItem: Codable, Equatable, Sendable {
    case message(AgentMessageItem)
    /// Replayable Responses output, kept in its original order for stateless continuation.
    case responseOutput([JSONValue])
    case toolCall(ToolCallItem)
    case toolResult(ToolResultItem)
    case handoff(HandoffItem)
    case guardrail(GuardrailItem)
    case approval(ApprovalItem)
    case compaction(CompactionItem)
}
