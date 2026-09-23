import Foundation

public struct AgentInterruption: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let toolCall: ToolCallItem
    public let summary: String
    public let riskLevel: RiskLevel
    public let requestedAt: Date

    public init(
        id: UUID = UUID(),
        runID: UUID,
        toolCall: ToolCallItem,
        summary: String,
        riskLevel: RiskLevel,
        requestedAt: Date = .now
    ) {
        self.id = id
        self.runID = runID
        self.toolCall = toolCall
        self.summary = summary
        self.riskLevel = riskLevel
        self.requestedAt = requestedAt
    }
}
