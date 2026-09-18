import Foundation

enum ApprovalDecision: Codable, Equatable, Sendable {
    case approved
    case rejected(reason: String?)
}

enum RiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
}
