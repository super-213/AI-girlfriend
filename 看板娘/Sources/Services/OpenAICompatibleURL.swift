import Foundation

/// Converts a user-supplied base URL or a legacy complete endpoint into request URLs.
enum OpenAICompatibleURL {
    static func baseURLString(from address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .lowercased().hasSuffix("chat/completions") else {
            return trimmed
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let basePath = String(path.dropLast("chat/completions".count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "" : "/" + basePath
        return components.string ?? trimmed
    }

    static func chatEndpoint(from address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let loweredPath = path.lowercased()
        // Existing Responses API profiles are explicit endpoints.
        if loweredPath.hasSuffix("chat/completions") || loweredPath.hasSuffix("responses") {
            return components.url
        }
        components.path = "/" + (path.isEmpty ? "chat/completions" : path + "/chat/completions")
        return components.url
    }
}
