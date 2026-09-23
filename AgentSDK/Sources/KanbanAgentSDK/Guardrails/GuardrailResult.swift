import Foundation

public enum GuardrailAction: String, Codable, Sendable {
    case allow
    case stop
    case requireApproval
}

public enum GuardrailStage: String, Codable, Sendable {
    case input
    case toolInput
    case toolOutput
    case output
}

public struct GuardrailResult: Codable, Equatable, Sendable {
    public let action: GuardrailAction
    public let message: String
    public let guardrailName: String?
    public let stage: GuardrailStage?
    public let toolCallID: String?

    public init(
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

    public static let allowed = GuardrailResult(action: .allow, message: "")
}
