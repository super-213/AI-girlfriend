import Foundation

struct RunState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let runID: UUID
    let currentAgentID: String
    let turn: Int
    let completedItems: [AgentItem]
    let pendingToolCalls: [ToolCallItem]
    let interruptions: [AgentInterruption]
    let approvalResolutionsByToolCallID: [String: ApprovalResolution]
    let contextCompaction: CompactionItem?
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
        approvalResolutionsByToolCallID: [String: ApprovalResolution] = [:],
        contextCompaction: CompactionItem? = nil,
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
        self.approvalResolutionsByToolCallID = approvalResolutionsByToolCallID
        self.contextCompaction = contextCompaction
        self.providerContinuationID = providerContinuationID
        self.rawResponses = rawResponses
        self.usage = usage
        self.traceID = traceID
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runID, currentAgentID, turn, completedItems
        case pendingToolCalls, interruptions, approvalResolutionsByToolCallID
        case contextCompaction, providerContinuationID, rawResponses, usage
        case traceID, sessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        runID = try container.decode(UUID.self, forKey: .runID)
        currentAgentID = try container.decode(String.self, forKey: .currentAgentID)
        turn = try container.decode(Int.self, forKey: .turn)
        completedItems = try container.decode([AgentItem].self, forKey: .completedItems)
        pendingToolCalls = try container.decode([ToolCallItem].self, forKey: .pendingToolCalls)
        interruptions = try container.decode([AgentInterruption].self, forKey: .interruptions)
        approvalResolutionsByToolCallID = try container.decodeIfPresent(
            [String: ApprovalResolution].self,
            forKey: .approvalResolutionsByToolCallID
        ) ?? [:]
        contextCompaction = try container.decodeIfPresent(
            CompactionItem.self,
            forKey: .contextCompaction
        )
        providerContinuationID = try container.decodeIfPresent(
            String.self,
            forKey: .providerContinuationID
        )
        rawResponses = try container.decodeIfPresent(
            [ModelResponse].self,
            forKey: .rawResponses
        ) ?? []
        usage = try container.decodeIfPresent(AgentUsage.self, forKey: .usage) ?? .zero
        traceID = try container.decode(UUID.self, forKey: .traceID)
        sessionID = try container.decode(String.self, forKey: .sessionID)
    }
}
