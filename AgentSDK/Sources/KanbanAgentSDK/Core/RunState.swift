import Foundation

public struct RunState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let runID: UUID
    public let currentAgentID: String
    public let turn: Int
    public let completedItems: [AgentItem]
    public let pendingToolCalls: [ToolCallItem]
    public let interruptions: [AgentInterruption]
    public let approvalResolutionsByToolCallID: [String: ApprovalResolution]
    public let contextCompaction: CompactionItem?
    public let providerContinuationID: String?
    public let rawResponses: [ModelResponse]
    public let usage: AgentUsage
    public let guardrailResults: [GuardrailResult]
    public let traceID: UUID
    public let sessionID: String

    public init(
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
        guardrailResults: [GuardrailResult] = [],
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
        self.guardrailResults = guardrailResults
        self.traceID = traceID
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, runID, currentAgentID, turn, completedItems
        case pendingToolCalls, interruptions, approvalResolutionsByToolCallID
        case contextCompaction, providerContinuationID, rawResponses, usage, guardrailResults
        case traceID, sessionID
    }

    public init(from decoder: Decoder) throws {
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
        guardrailResults = try container.decodeIfPresent(
            [GuardrailResult].self,
            forKey: .guardrailResults
        ) ?? []
        traceID = try container.decode(UUID.self, forKey: .traceID)
        sessionID = try container.decode(String.self, forKey: .sessionID)
    }
}
