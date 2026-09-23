import Foundation

public struct ModelCapabilities: Codable, Equatable, Sendable {
    public let supportsTools: Bool
    public let supportsParallelTools: Bool
    public let supportsStructuredOutput: Bool
    public let supportsImageInput: Bool
    public let supportsServerManagedState: Bool
    public let supportsPromptCaching: Bool
    public let supportsResponsesAPI: Bool

    public init(
        supportsTools: Bool,
        supportsParallelTools: Bool,
        supportsStructuredOutput: Bool,
        supportsImageInput: Bool,
        supportsServerManagedState: Bool,
        supportsPromptCaching: Bool,
        supportsResponsesAPI: Bool
    ) {
        self.supportsTools = supportsTools
        self.supportsParallelTools = supportsParallelTools
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsImageInput = supportsImageInput
        self.supportsServerManagedState = supportsServerManagedState
        self.supportsPromptCaching = supportsPromptCaching
        self.supportsResponsesAPI = supportsResponsesAPI
    }

    public static let chatCompletions = ModelCapabilities(
        supportsTools: true,
        supportsParallelTools: false,
        supportsStructuredOutput: false,
        supportsImageInput: true,
        supportsServerManagedState: false,
        supportsPromptCaching: false,
        supportsResponsesAPI: false
    )
}
