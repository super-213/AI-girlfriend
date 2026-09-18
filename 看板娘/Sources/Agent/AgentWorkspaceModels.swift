//
//  AgentWorkspaceModels.swift
//  看板娘
//
//  File authorization, audit, result artifacts and undo support for desktop work.
//

import Combine
import Foundation

enum AgentWorkspaceSettings {
    static let requireDirectoryAuthorizationKey = "agent.workspace.requireDirectoryAuthorization"
    static let showCloudTransferNoticeKey = "agent.workspace.showCloudTransferNotice"
    static let showDirectoryAccessStatusKey = "agent.workspace.showDirectoryAccessStatus"
    static let showToolAuditInConversationKey = "agent.workspace.showToolAuditInConversation"
    static let authorizedDirectoriesKey = "agent.workspace.authorizedDirectories"
    static let auditEntriesKey = "agent.workspace.auditEntries"
    static let undoRecordsKey = "agent.workspace.undoRecords"

    static func isCloudModel(defaults: UserDefaults = .standard) -> Bool {
        if (defaults.string(forKey: "provider") ?? ModelProvider.zhipu.rawValue).lowercased() == "ollama" {
            return false
        }
        if let rawURL = defaults.string(forKey: "apiUrl"),
           let host = URL(string: rawURL)?.host?.lowercased(),
           host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return false
        }
        return true
    }
}

@MainActor
final class AgentFileAccessStore: ObservableObject {
    static let shared = AgentFileAccessStore()

    @Published private(set) var authorizedDirectories: [String]
    private var sessionGrantedPaths = Set<String>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorizedDirectories = (defaults.stringArray(forKey: AgentWorkspaceSettings.authorizedDirectoriesKey) ?? [])
            .map(Self.standardized)
            .uniqued()
    }

    var requiresAuthorization: Bool {
        defaults.bool(forKey: AgentWorkspaceSettings.requireDirectoryAuthorizationKey)
    }

    func grantSessionAccess(to urls: [URL]) {
        for url in urls where url.isFileURL {
            sessionGrantedPaths.insert(Self.standardized(url.path))
        }
    }

    func addAuthorizedDirectory(_ url: URL) {
        let path = Self.standardized(url.path)
        guard !authorizedDirectories.contains(path) else { return }
        authorizedDirectories.append(path)
        authorizedDirectories.sort()
        persist()
    }

    func removeAuthorizedDirectory(_ path: String) {
        authorizedDirectories.removeAll { $0 == Self.standardized(path) }
        persist()
    }

    func canRead(_ path: String) -> Bool {
        guard requiresAuthorization else { return true }
        let resolved = Self.standardized(path)
        return sessionGrantedPaths.contains(where: { Self.contains(root: $0, path: resolved) })
            || authorizedDirectories.contains(where: { Self.contains(root: $0, path: resolved) })
    }

    func canWrite(_ path: String) -> Bool {
        guard requiresAuthorization else { return true }
        let resolved = Self.standardized(path)
        if sessionGrantedPaths.contains(resolved) { return true }
        return canRead(URL(fileURLWithPath: resolved).deletingLastPathComponent().path)
    }

    func searchableRoots(requestedDirectory: String?) -> [URL]? {
        if let requestedDirectory {
            guard canRead(requestedDirectory) else { return nil }
            return [URL(fileURLWithPath: requestedDirectory, isDirectory: true)]
        }
        guard requiresAuthorization else { return [] }
        return authorizedDirectories.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func makePolicy(additionalRoots: [String] = []) -> AgentFileAccessPolicy {
        let roots = (authorizedDirectories + Array(sessionGrantedPaths) + additionalRoots)
            .map(Self.standardized)
            .uniqued()
        return AgentFileAccessPolicy(
            requiresAuthorization: requiresAuthorization,
            readableRoots: roots,
            writableRoots: roots
        )
    }

    static func denialMessage(path: String) -> String {
        "路径尚未授权：\(path)。请将文件拖给角色，或在偏好设置 → 命令权限 → 文件与工具中添加允许的目录。"
    }

    private func persist() {
        defaults.set(authorizedDirectories, forKey: AgentWorkspaceSettings.authorizedDirectoriesKey)
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }

    private static func contains(root: String, path: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}

struct AgentToolAuditEntry: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case requested
        case approved
        case declined
        case running
        case succeeded
        case failed

        var title: String {
            switch self {
            case .requested: return "待确认"
            case .approved: return "已批准"
            case .declined: return "已拒绝"
            case .running: return "执行中"
            case .succeeded: return "已完成"
            case .failed: return "失败"
            }
        }
    }

    let id: UUID
    let toolName: String
    let summary: String
    let status: Status
    let detail: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        toolName: String,
        summary: String,
        status: Status,
        detail: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.toolName = toolName
        self.summary = SensitiveDataRedactor.redact(summary)
        self.status = status
        self.detail = detail.map { SensitiveDataRedactor.redact($0) }
        self.createdAt = createdAt
    }
}

@MainActor
final class AgentToolAuditStore: ObservableObject {
    static let shared = AgentToolAuditStore()
    @Published private(set) var entries: [AgentToolAuditEntry]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AgentWorkspaceSettings.auditEntriesKey),
           let decoded = try? JSONDecoder().decode([AgentToolAuditEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    func record(
        toolName: String,
        summary: String,
        status: AgentToolAuditEntry.Status,
        detail: String? = nil
    ) {
        entries.insert(AgentToolAuditEntry(
            toolName: toolName,
            summary: summary,
            status: status,
            detail: detail
        ), at: 0)
        entries = Array(entries.prefix(300))
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: AgentWorkspaceSettings.auditEntriesKey)
    }
}

struct AgentFileResult: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let isDirectory: Bool
    let sizeBytes: Int?
    let modifiedAt: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isDirectory: Bool,
        sizeBytes: Int? = nil,
        modifiedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
    }
}

enum DialogArtifactKind: String, Codable {
    case fileResults
    case actionPlan
    case fileChange
}

struct DialogArtifact: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: DialogArtifactKind
    let title: String
    let detail: String?
    let files: [AgentFileResult]

    init(
        id: UUID = UUID(),
        kind: DialogArtifactKind,
        title: String,
        detail: String? = nil,
        files: [AgentFileResult] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.files = files
    }
}

struct AgentUndoRecord: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case removeCreated
        case restoreBackup
        case moveBack
    }

    let id: UUID
    let kind: Kind
    let originalPath: String
    let currentPath: String?
    let backupPath: String?
    let summary: String
    let createdAt: Date
}

@MainActor
final class AgentFileUndoStore {
    static let shared = AgentFileUndoStore()
    private let defaults: UserDefaults
    private(set) var records: [AgentUndoRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: AgentWorkspaceSettings.undoRecordsKey),
           let decoded = try? JSONDecoder().decode([AgentUndoRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    var latest: AgentUndoRecord? { records.first }

    func prepareBackup(for path: String) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-agent-undo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: destination)
        return destination.path
    }

    func push(
        kind: AgentUndoRecord.Kind,
        originalPath: String,
        currentPath: String? = nil,
        backupPath: String? = nil,
        summary: String
    ) {
        records.insert(AgentUndoRecord(
            id: UUID(),
            kind: kind,
            originalPath: originalPath,
            currentPath: currentPath,
            backupPath: backupPath,
            summary: summary,
            createdAt: .now
        ), at: 0)
        records = Array(records.prefix(30))
        persist()
    }

    func undoLatest() -> Result<String, Error> {
        guard let record = records.first else {
            return .failure(NSError(domain: "AgentUndo", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可撤销的文件操作"]))
        }
        do {
            switch record.kind {
            case .removeCreated:
                if FileManager.default.fileExists(atPath: record.originalPath) {
                    try FileManager.default.removeItem(atPath: record.originalPath)
                }
            case .restoreBackup:
                guard let backupPath = record.backupPath else { throw undoError("撤销备份不存在") }
                if FileManager.default.fileExists(atPath: record.originalPath) {
                    try FileManager.default.removeItem(atPath: record.originalPath)
                }
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: backupPath),
                    to: URL(fileURLWithPath: record.originalPath)
                )
                try? FileManager.default.removeItem(atPath: backupPath)
            case .moveBack:
                guard let currentPath = record.currentPath,
                      FileManager.default.fileExists(atPath: currentPath),
                      !FileManager.default.fileExists(atPath: record.originalPath) else {
                    throw undoError("文件已被其他操作改变，无法安全撤销")
                }
                try FileManager.default.moveItem(
                    at: URL(fileURLWithPath: currentPath),
                    to: URL(fileURLWithPath: record.originalPath)
                )
            }
            records.removeFirst()
            persist()
            return .success("已撤销：\(record.summary)")
        } catch {
            return .failure(error)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: AgentWorkspaceSettings.undoRecordsKey)
    }

    private func undoError(_ message: String) -> Error {
        NSError(domain: "AgentUndo", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
