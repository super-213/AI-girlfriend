import Foundation
import Testing
@testable import 看板娘

private final class DiagnosticURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: ["x-request-id": "req-123", "retry-after": "30"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"code":"quota_exceeded","message":"secret-token"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct ProviderDiagnosticsTests {
    private func transport() -> URLSessionAgentHTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiagnosticURLProtocol.self]
        return URLSessionAgentHTTPTransport(session: URLSession(configuration: configuration))
    }

    @Test
    func httpErrorShowsStatusBodyAndRequestIDWithoutAPIKey() async {
        var request = URLRequest(url: URL(string: "https://example.test/chat?api_key=secret-token")!)
        request.httpMethod = "POST"
        request.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")
        do {
            for try await _ in transport().streamLines(request: request, runID: UUID()) {}
            Issue.record("HTTP 429 应返回错误")
        } catch let error as ModelProviderError {
            let message = AgentError.modelRequestFailed(error).localizedDescription
            #expect(message.contains("HTTP 429"))
            #expect(message.contains("quota_exceeded"))
            #expect(message.contains("req-123"))
            #expect(message.contains("retry-after：30"))
            #expect(!message.contains("secret-token"))
            #expect(!message.contains("api_key="))
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }

    @Test
    func networkErrorShowsUnderlyingDomainAndCode() async {
        let request = URLRequest(url: URL(string: "https://example.test/timeout")!)
        do {
            for try await _ in transport().streamLines(request: request, runID: UUID()) {}
            Issue.record("超时应返回错误")
        } catch let error as ModelProviderError {
            let message = error.localizedDescription
            #expect(message.contains("NSURLErrorDomain"))
            #expect(message.contains("-1001"))
            #expect(message.contains("example.test/timeout"))
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }

    @Test
    func streamErrorPreservesProviderCodeAndMessage() {
        do {
            _ = try AgentProviderWireSupport.jsonObject(
                from: #"data: {"error":{"code":"insufficient_quota","message":"额度不足"}}"#
            )
        } catch let error as ModelProviderError {
            #expect(error.localizedDescription.contains("insufficient_quota"))
            #expect(error.localizedDescription.contains("额度不足"))
        } catch {
            Issue.record("错误类型不正确：\(error)")
        }
    }
}
