import Foundation

struct OpenAICompatibleChatProvider: AgentModelProvider {
    private let base: HTTPAgentModelProvider
    var id: String { base.id }
    var capabilities: ModelCapabilities { base.capabilities }

    init(
        configuration: AgentProviderConfiguration,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport.shared
    ) {
        base = HTTPAgentModelProvider(
            configuration: configuration,
            codec: ChatCompletionProviderCodec(flavor: .openAICompatible),
            transport: transport
        )
    }

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        base.streamResponse(request: request)
    }

    func cancel(runID: UUID) async { await base.cancel(runID: runID) }
}
