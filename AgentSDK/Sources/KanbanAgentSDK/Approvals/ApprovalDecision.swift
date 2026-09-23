import Foundation

public enum ApprovalDecision: Codable, Equatable, Sendable {
    case approved
    case rejected(reason: String?)
}

public struct ApprovalResolution: Codable, Equatable, Sendable {
    public let interruptionID: UUID
    public let decision: ApprovalDecision
}

public enum RiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}
