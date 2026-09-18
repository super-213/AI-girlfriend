import Foundation

enum MCPNetworkBoundary: String, Codable, Sendable {
    case local
    case privateNetwork
    case remoteHTTPS
}

struct MCPServerConfiguration: Codable, Equatable, Sendable {
    let id: String
    let label: String
    let endpoint: URL
    let networkBoundary: MCPNetworkBoundary

    init(id: String, label: String, endpoint: URL, networkBoundary: MCPNetworkBoundary) {
        self.id = id
        self.label = label
        self.endpoint = endpoint
        self.networkBoundary = networkBoundary
    }

    func validate() throws {
        guard let scheme = endpoint.scheme?.lowercased(), let host = endpoint.host?.lowercased() else {
            throw AgentError.invalidConfiguration("MCP Server 缺少有效 endpoint")
        }
        switch networkBoundary {
        case .local:
            let localHosts = Set(["localhost", "127.0.0.1", "::1"])
            guard localHosts.contains(host), scheme == "http" || scheme == "https" else {
                throw AgentError.invalidConfiguration("本地 MCP 只允许 loopback HTTP(S) endpoint")
            }
        case .privateNetwork:
            guard scheme == "https" else {
                throw AgentError.invalidConfiguration("私有 MCP 必须使用 HTTPS")
            }
        case .remoteHTTPS:
            guard scheme == "https" else {
                throw AgentError.invalidConfiguration("远程 MCP 必须使用 HTTPS")
            }
        }
    }
}

enum MCPApprovalPolicy: Codable, Equatable, Sendable {
    case never
    case always
    case mutations
    case selected(Set<String>)

    func requiresApproval(tool: MCPToolDescriptor) -> Bool {
        switch self {
        case .never: false
        case .always: true
        case .mutations: !tool.isReadOnly || tool.hasExternalSideEffects
        case .selected(let names): names.contains(tool.name)
        }
    }
}

struct MCPToolFilter: Codable, Equatable, Sendable {
    let allowedNames: Set<String>?
    let blockedNames: Set<String>

    init(allowedNames: Set<String>? = nil, blockedNames: Set<String> = []) {
        self.allowedNames = allowedNames
        self.blockedNames = blockedNames
    }

    func allows(_ descriptor: MCPToolDescriptor) -> Bool {
        !blockedNames.contains(descriptor.name)
            && (allowedNames == nil || allowedNames?.contains(descriptor.name) == true)
    }
}

struct MCPToolDescriptor: Codable, Equatable, Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let isReadOnly: Bool
    let isIdempotent: Bool
    let hasExternalSideEffects: Bool

    init(
        name: String,
        description: String,
        inputSchema: JSONValue,
        isReadOnly: Bool = true,
        isIdempotent: Bool = true,
        hasExternalSideEffects: Bool = false
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.isReadOnly = isReadOnly
        self.isIdempotent = isIdempotent
        self.hasExternalSideEffects = hasExternalSideEffects
    }
}

struct MCPCallResult: Codable, Equatable, Sendable {
    let content: String
    let imagePaths: [String]
    let isError: Bool

    init(content: String, imagePaths: [String] = [], isError: Bool = false) {
        self.content = content
        self.imagePaths = imagePaths
        self.isError = isError
    }
}

protocol MCPToolClient: Sendable {
    func listTools(server: MCPServerConfiguration) async throws -> [MCPToolDescriptor]
    func callTool(
        server: MCPServerConfiguration,
        name: String,
        arguments: JSONValue
    ) async throws -> MCPCallResult
}
