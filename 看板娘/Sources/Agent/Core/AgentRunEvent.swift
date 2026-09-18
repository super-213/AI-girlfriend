import Foundation

struct RunSnapshot: Sendable, Equatable {
    let runID: UUID
    let sessionID: String
    let startedAt: Date
}

struct AgentSnapshot: Sendable, Equatable {
    let id: String
    let name: String
}

struct ModelRequestSnapshot: Sendable, Equatable {
    let turn: Int
    let providerID: String
    let modelID: String
}

struct ModelResponseSnapshot: Sendable, Equatable {
    let turn: Int
    let response: ModelResponse
}

struct HandoffEvent: Sendable, Equatable {
    let sourceAgentID: String
    let targetAgentID: String
}

struct CompactionEvent: Sendable, Equatable {
    let summarizedItemCount: Int
}

enum AgentRunEvent: Sendable, Equatable {
    case runStarted(RunSnapshot)
    case agentStarted(AgentSnapshot)
    case modelStarted(ModelRequestSnapshot)
    case textDelta(String)
    case modelCompleted(ModelResponseSnapshot)
    case toolCallStarted(ToolCallItem)
    case toolCallCompleted(ToolResultItem)
    case approvalRequired(AgentInterruption)
    case handoff(HandoffEvent)
    case contextCompactionStarted
    case contextCompacted(CompactionEvent)
    case usageUpdated(AgentUsage)
    case runCompleted
    case runFailed(AgentError)
}
