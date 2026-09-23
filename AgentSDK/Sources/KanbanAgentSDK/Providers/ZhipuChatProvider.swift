import Foundation

public struct ZhipuChatProvider: AgentModelProvider {
    private let base: HTTPAgentModelProvider
    public var id: String { base.id }
    public var capabilities: ModelCapabilities { base.capabilities }

    public init(
        configuration: AgentProviderConfiguration,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport.shared
    ) {
        base = HTTPAgentModelProvider(
            configuration: configuration,
            codec: ChatCompletionProviderCodec(flavor: .zhipu),
            transport: transport
        )
    }

    public func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        base.streamResponse(request: request)
    }

    public func cancel(runID: UUID) async { await base.cancel(runID: runID) }
}
