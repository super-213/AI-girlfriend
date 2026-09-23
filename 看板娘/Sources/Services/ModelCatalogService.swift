import Foundation

/// Discovers model IDs for the endpoint currently being edited in Preferences.
struct ModelCatalogService {
    enum CatalogError: LocalizedError {
        case invalidURL
        case unavailable

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "请先填写有效的 API 地址"
            case .unavailable: return "服务未提供模型列表，请手动填写模型 ID"
            }
        }
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func catalogURLs(for configuration: ModelConfiguration) -> [URL] {
        let rawURL = configuration.apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return [] }

        components.query = nil
        components.fragment = nil
        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix("chat/completions") {
            path = String(path.dropLast("chat/completions".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if configuration.providerKind == .ollama && path.lowercased().hasSuffix("api/chat") {
            path = String(path.dropLast("api/chat".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            path = path.isEmpty ? "v1" : path + "/v1"
        }
        components.path = "/" + (path.isEmpty ? "models" : path + "/models")

        var result: [URL] = []
        if let standardURL = components.url { result.append(standardURL) }

        switch configuration.providerKind {
        case .openAICompatible:
            // DashScope's native catalog has a different response shape.
            let host = components.host?.lowercased() ?? ""
            if host == "dashscope.aliyuncs.com" || host.hasSuffix(".maas.aliyuncs.com") {
                components.path = "/api/v1/models"
                components.queryItems = [
                    URLQueryItem(name: "page_no", value: "1"),
                    URLQueryItem(name: "page_size", value: "100")
                ]
                if let fallback = components.url { result.append(fallback) }
            }
        case .ollama:
            components.path = "/api/tags"
            if let fallback = components.url { result.append(fallback) }
        case .zhipu:
            break
        }
        return result
    }

    func models(for configuration: ModelConfiguration) async throws -> [String] {
        let urls = Self.catalogURLs(for: configuration)
        guard !urls.isEmpty else { throw CatalogError.invalidURL }

        for (index, url) in urls.enumerated() {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && configuration.providerKind != .ollama {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else { continue }
                let models = Self.parseModels(data, fallback: index > 0 ? configuration.providerKind : nil)
                if !models.isEmpty { return models }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An unavailable standard endpoint can still have a native catalog.
                continue
            }
        }
        throw CatalogError.unavailable
    }

    static func parseModels(_ data: Data, fallback: ModelProvider? = nil) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let rows: [[String: Any]]
        switch fallback {
        case .openAICompatible:
            rows = (json["output"] as? [String: Any])?["models"] as? [[String: Any]] ?? []
        case .ollama:
            rows = json["models"] as? [[String: Any]] ?? []
        default:
            rows = json["data"] as? [[String: Any]] ?? []
        }
        let key = fallback == .openAICompatible ? "model" : fallback == .ollama ? "name" : "id"
        return Array(Set(rows.compactMap { ($0[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
