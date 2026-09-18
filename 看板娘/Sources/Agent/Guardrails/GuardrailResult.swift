import Foundation

enum GuardrailAction: String, Codable, Sendable {
    case allow
    case stop
    case requireApproval
}

enum GuardrailStage: String, Codable, Sendable {
    case input
    case toolInput
    case toolOutput
    case output
}

struct GuardrailResult: Codable, Equatable, Sendable {
    let action: GuardrailAction
    let message: String
    let guardrailName: String?
    let stage: GuardrailStage?
    let toolCallID: String?

    init(
        action: GuardrailAction,
        message: String,
        guardrailName: String? = nil,
        stage: GuardrailStage? = nil,
        toolCallID: String? = nil
    ) {
        self.action = action
        self.message = message
        self.guardrailName = guardrailName
        self.stage = stage
        self.toolCallID = toolCallID
    }

    static let allowed = GuardrailResult(action: .allow, message: "")
}
