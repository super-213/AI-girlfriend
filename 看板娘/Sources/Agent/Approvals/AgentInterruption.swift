import Foundation

struct AgentInterruption: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let runID: UUID
    let toolCall: ToolCallItem
    let summary: String
    let riskLevel: RiskLevel
    let requestedAt: Date

    init(
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
