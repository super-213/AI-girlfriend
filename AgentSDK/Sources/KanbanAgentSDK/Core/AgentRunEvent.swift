import Foundation

public struct RunSnapshot: Sendable, Equatable {
    public let runID: UUID
    public let sessionID: String
    public let startedAt: Date
}

public struct AgentSnapshot: Sendable, Equatable {
    public let id: String
    public let name: String
}

public struct ModelRequestSnapshot: Sendable, Equatable {
    public let turn: Int
    public let providerID: String
    public let modelID: String
}

public struct ModelResponseSnapshot: Sendable, Equatable {
    public let turn: Int
    public let response: ModelResponse
}

public struct HandoffEvent: Sendable, Equatable {
    public let sourceAgentID: String
    public let targetAgentID: String
    public let reason: String
    public let metadata: JSONValue?

    public init(
        sourceAgentID: String,
        targetAgentID: String,
        reason: String = "",
        metadata: JSONValue? = nil
    ) {
        self.sourceAgentID = sourceAgentID
        self.targetAgentID = targetAgentID
        self.reason = reason
        self.metadata = metadata
    }
}

public struct CompactionEvent: Sendable, Equatable {
    public let summarizedItemCount: Int
    public let retainedItemCount: Int
    public let estimatedTokensBeforeCompaction: Int

    public init(
        summarizedItemCount: Int,
        retainedItemCount: Int = 0,
        estimatedTokensBeforeCompaction: Int = 0
    ) {
        self.summarizedItemCount = summarizedItemCount
        self.retainedItemCount = retainedItemCount
        self.estimatedTokensBeforeCompaction = estimatedTokensBeforeCompaction
    }
}

public enum AgentRunEvent: Sendable, Equatable {
    case runStarted(RunSnapshot)
    case agentStarted(AgentSnapshot)
    case modelStarted(ModelRequestSnapshot)
    case textDelta(String)
    case modelCompleted(ModelResponseSnapshot)
    case toolCallStarted(ToolCallItem)
    case toolCallCompleted(ToolResultItem)
    case guardrailEvaluated(GuardrailResult)
    case approvalRequired(AgentInterruption)
    case handoff(HandoffEvent)
    case contextCompactionStarted
    case contextCompacted(CompactionEvent)
    case usageUpdated(AgentUsage)
    case runCompleted
    case runFailed(AgentError)
}
