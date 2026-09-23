import Foundation

public enum MCPNetworkBoundary: String, Codable, Sendable {
    case local
    case privateNetwork
    case remoteHTTPS
}

public struct MCPServerConfiguration: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let endpoint: URL
    public let networkBoundary: MCPNetworkBoundary

    public init(id: String, label: String, endpoint: URL, networkBoundary: MCPNetworkBoundary) {
        self.id = id
        self.label = label
        self.endpoint = endpoint
        self.networkBoundary = networkBoundary
    }

    public func validate() throws {
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

public enum MCPApprovalPolicy: Codable, Equatable, Sendable {
    case never
    case always
    case mutations
    case selected(Set<String>)

    public func requiresApproval(tool: MCPToolDescriptor) -> Bool {
        switch self {
        case .never: false
        case .always: true
        case .mutations: !tool.isReadOnly || tool.hasExternalSideEffects
        case .selected(let names): names.contains(tool.name)
        }
    }
}

public struct MCPToolFilter: Codable, Equatable, Sendable {
    public let allowedNames: Set<String>?
    public let blockedNames: Set<String>

    public init(allowedNames: Set<String>? = nil, blockedNames: Set<String> = []) {
        self.allowedNames = allowedNames
        self.blockedNames = blockedNames
    }

    public func allows(_ descriptor: MCPToolDescriptor) -> Bool {
        !blockedNames.contains(descriptor.name)
            && (allowedNames == nil || allowedNames?.contains(descriptor.name) == true)
    }
}

public struct MCPToolDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let isReadOnly: Bool
    public let isIdempotent: Bool
    public let hasExternalSideEffects: Bool

    public init(
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

public struct MCPCallResult: Codable, Equatable, Sendable {
    public let content: String
    public let imagePaths: [String]
    public let isError: Bool

    public init(content: String, imagePaths: [String] = [], isError: Bool = false) {
        self.content = content
        self.imagePaths = imagePaths
        self.isError = isError
    }
}

public protocol MCPToolClient: Sendable {
    func listTools(server: MCPServerConfiguration) async throws -> [MCPToolDescriptor]
    func callTool(
        server: MCPServerConfiguration,
        name: String,
        arguments: JSONValue
    ) async throws -> MCPCallResult
}
