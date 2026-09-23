import Foundation

public struct ToolDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue = .object([:])) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ToolBehavior: Sendable {
    public var isReadOnly: Bool
    public var isIdempotent: Bool
    public var hasExternalSideEffects: Bool
    public var requiresApproval: Bool
    public var allowsParallelExecution: Bool
    public var defaultTimeout: Duration?
    public var allowsAutomaticRetry: Bool
    public var riskLevel: RiskLevel

    public static let readOnly = ToolBehavior(
        isReadOnly: true,
        isIdempotent: true,
        hasExternalSideEffects: false,
        requiresApproval: false,
        allowsParallelExecution: true,
        defaultTimeout: nil,
        allowsAutomaticRetry: true,
        riskLevel: .low
    )

    public static let mutating = ToolBehavior(
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
