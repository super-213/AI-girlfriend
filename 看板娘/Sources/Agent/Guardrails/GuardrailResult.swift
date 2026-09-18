import Foundation

enum GuardrailAction: String, Codable, Sendable {
    case allow
    case stop
    case requireApproval
}

struct GuardrailResult: Codable, Equatable, Sendable {
    let action: GuardrailAction
    let message: String

    static let allowed = GuardrailResult(action: .allow, message: "")
}
