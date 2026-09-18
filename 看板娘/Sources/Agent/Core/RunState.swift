import Foundation

struct RunState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let runID: UUID
    let currentAgentID: String
    let turn: Int
    let completedItems: [AgentItem]
    let pendingToolCalls: [ToolCallItem]
    let interruptions: [AgentInterruption]
    let providerContinuationID: String?
    let rawResponses: [ModelResponse]
    let usage: AgentUsage
    let traceID: UUID
    let sessionID: String

    init(
        schemaVersion: Int = RunState.currentSchemaVersion,
        runID: UUID,
        currentAgentID: String,
        turn: Int,
        completedItems: [AgentItem],
        pendingToolCalls: [ToolCallItem],
        interruptions: [AgentInterruption],
        providerContinuationID: String? = nil,
        rawResponses: [ModelResponse] = [],
        usage: AgentUsage = .zero,
        traceID: UUID,
        sessionID: String
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.currentAgentID = currentAgentID
        self.turn = turn
        self.completedItems = completedItems
        self.pendingToolCalls = pendingToolCalls
        self.interruptions = interruptions
        self.providerContinuationID = providerContinuationID
        self.rawResponses = rawResponses
        self.usage = usage
        self.traceID = traceID
        self.sessionID = sessionID
    }
}
