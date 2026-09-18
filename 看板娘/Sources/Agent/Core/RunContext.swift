import Foundation

struct AgentFileAccessPolicy: Codable, Equatable, Sendable {
    var requiresAuthorization: Bool
    var readableRoots: [String]
    var writableRoots: [String]

    init(
        requiresAuthorization: Bool = false,
        readableRoots: [String] = [],
        writableRoots: [String] = []
    ) {
        self.requiresAuthorization = requiresAuthorization
        self.readableRoots = Self.unique(readableRoots.map(Self.standardized))
        self.writableRoots = Self.unique(writableRoots.map(Self.standardized))
    }

    static let inherited = AgentFileAccessPolicy()

    func canRead(_ path: String) -> Bool {
        guard requiresAuthorization else { return true }
        let path = Self.standardized(path)
        return readableRoots.contains { Self.contains(root: $0, path: path) }
            || writableRoots.contains { Self.contains(root: $0, path: path) }
    }

    func canWrite(_ path: String) -> Bool {
        guard requiresAuthorization else { return true }
        let path = Self.standardized(path)
        return writableRoots.contains { Self.contains(root: $0, path: path) }
            || writableRoots.contains {
                Self.contains(
                    root: $0,
                    path: URL(fileURLWithPath: path).deletingLastPathComponent().path
                )
            }
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL.path
    }

    private static func contains(root: String, path: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}

struct AppAgentContext: Sendable {
    let conversationID: UUID
    let projectID: UUID?
    let workspacePath: String?
    let characterID: String?
    let fileAccessPolicy: AgentFileAccessPolicy
    let commandPermissionPolicy: CommandPermissionPolicy

    init(
        conversationID: UUID,
        projectID: UUID? = nil,
        workspacePath: String? = nil,
        characterID: String? = nil,
        fileAccessPolicy: AgentFileAccessPolicy = .inherited,
        commandPermissionPolicy: CommandPermissionPolicy = CommandPermissionPolicy()
    ) {
        self.conversationID = conversationID
        self.projectID = projectID
        self.workspacePath = workspacePath
        self.characterID = characterID
        self.fileAccessPolicy = fileAccessPolicy
        self.commandPermissionPolicy = commandPermissionPolicy
    }
}
