import Foundation

enum ApprovalDecision: Codable, Equatable, Sendable {
    case approved
    case rejected(reason: String?)
}

struct ApprovalResolution: Codable, Equatable, Sendable {
    let interruptionID: UUID
    let decision: ApprovalDecision
}

enum RiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}
