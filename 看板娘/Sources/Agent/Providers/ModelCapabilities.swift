import Foundation

struct ModelCapabilities: Codable, Equatable, Sendable {
    let supportsTools: Bool
    let supportsParallelTools: Bool
    let supportsStructuredOutput: Bool
    let supportsImageInput: Bool
    let supportsServerManagedState: Bool
    let supportsPromptCaching: Bool
    let supportsResponsesAPI: Bool

    static let chatCompletions = ModelCapabilities(
        supportsTools: true,
        supportsParallelTools: false,
        supportsStructuredOutput: false,
        supportsImageInput: true,
        supportsServerManagedState: false,
        supportsPromptCaching: false,
        supportsResponsesAPI: false
    )
}
