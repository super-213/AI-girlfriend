import Foundation

struct ToolDefinition: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let parameters: JSONValue

    init(name: String, description: String, parameters: JSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

struct ToolBehavior: Sendable {
    var isReadOnly: Bool
    var isIdempotent: Bool
    var hasExternalSideEffects: Bool
    var requiresApproval: Bool
    var allowsParallelExecution: Bool
    var defaultTimeout: Duration?
    var allowsAutomaticRetry: Bool
    var riskLevel: RiskLevel

    static let readOnly = ToolBehavior(
        isReadOnly: true,
        isIdempotent: true,
        hasExternalSideEffects: false,
        requiresApproval: false,
        allowsParallelExecution: true,
        defaultTimeout: nil,
        allowsAutomaticRetry: true,
        riskLevel: .low
    )

    static let mutating = ToolBehavior(
        isReadOnly: false,
        isIdempotent: false,
        hasExternalSideEffects: true,
        requiresApproval: true,
        allowsParallelExecution: false,
        defaultTimeout: nil,
        allowsAutomaticRetry: false,
        riskLevel: .high
    )
}
