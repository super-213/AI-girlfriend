import Foundation
import Testing
@testable import 看板娘

private final class ModelCatalogURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body: String
        let status: Int
        switch url.path {
        case "/compatible-mode/v1/models":
            status = 404
            body = "{}"
        case "/api/v1/models":
            status = request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key" ? 200 : 401
            body = #"{"output":{"models":[{"model":"qwen-plus"},{"model":"qwen-max"}]}}"#
        case "/v1/models":
            if url.port == 11434 {
                status = 404
                body = "{}"
            } else {
                status = 200
                body = #"{"object":"list","data":[{"id":"model-b"},{"id":"model-a"},{"id":"model-a"}]}"#
            }
        case "/api/tags":
            status = 200
            body = #"{"models":[{"name":"llama3:latest"},{"name":"qwen2.5:latest"}]}"#
        default:
            status = 200
            body = #"{"object":"list","data":[{"id":"model-b"},{"id":"model-a"},{"id":"model-a"}]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct ModelCatalogServiceTests {
    private func configuration(_ provider: ModelProvider, url: String, key: String = "") -> ModelConfiguration {
        ModelConfiguration(name: "Test", provider: provider.rawValue, aiModel: "", apiUrl: url, apiKey: key)
    }

    private func service() -> ModelCatalogService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelCatalogURLProtocol.self]
        return ModelCatalogService(session: URLSession(configuration: configuration))
    }

    @Test
    func standardModelsURLKeepsVersionPrefix() async throws {
        let config = configuration(.openAICompatible, url: "http://localhost:1234/v1/chat/completions")
        #expect(ModelCatalogService.catalogURLs(for: config).first?.absoluteString == "http://localhost:1234/v1/models")
        let baseConfig = configuration(.openAICompatible, url: "http://localhost:1234/v1/")
        #expect(ModelCatalogService.catalogURLs(for: baseConfig).first?.absoluteString == "http://localhost:1234/v1/models")
        #expect(try await service().models(for: config) == ["model-a", "model-b"])
    }

    @Test
    func dashScopeFallsBackToNativeCatalog() async throws {
        let config = configuration(.openAICompatible, url: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", key: "test-key")
        #expect(try await service().models(for: config) == ["qwen-max", "qwen-plus"])
    }

    @Test
    func ollamaFallsBackToTags() async throws {
        let config = configuration(.ollama, url: "http://localhost:11434/api/chat")
        #expect(ModelCatalogService.catalogURLs(for: config).first?.path == "/v1/models")
        #expect(try await service().models(for: config) == ["llama3:latest", "qwen2.5:latest"])
    }
}
