import Foundation

private enum CoreReadOnlyToolSupport {
    static func canRead(_ path: String) async -> Bool {
        await MainActor.run { AgentFileAccessStore.shared.canRead(path) }
    }

    static func denied(_ path: String, toolName: String) -> AgentError {
        .toolExecutionFailed(
            toolName: toolName,
            detail: "路径尚未授权：\(path)。请将文件拖给角色，或在偏好设置 → 命令权限 → 文件与工具中添加允许的目录。"
        )
    }

    static func trimmed(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

struct CurrentDateTimeAgentTool: AgentTool {
    struct Arguments: Codable, Sendable {}
    struct Output: Codable, Sendable {
        let localDatetime: String
        let timezone: String
        let utcOffsetSeconds: Int

        enum CodingKeys: String, CodingKey {
            case localDatetime = "local_datetime"
            case timezone
            case utcOffsetSeconds = "utc_offset_seconds"
        }
    }

    typealias Context = Void
    static let definition = ToolDefinition(
        name: "get_current_datetime",
        description: "读取用户 Mac 当前准确的本地日期、时间、星期和时区。凡是涉及今天、现在、日期、时间或星期的问题都应调用此工具。",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ])
    )

    func invoke(context: ToolContext<Void>, arguments: Arguments) async throws -> Output {
        try Task.checkCancellation()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss EEEE"
        return Output(
            localDatetime: formatter.string(from: .now),
            timezone: TimeZone.current.identifier,
            utcOffsetSeconds: TimeZone.current.secondsFromGMT()
        )
    }
}

struct ListDirectoryAgentTool: AgentTool {
    struct Arguments: Codable, Sendable { let path: String? }
    struct Output: Codable, Sendable {
        let path: String
        let entries: [String]
        let omittedCount: Int

        enum CodingKeys: String, CodingKey {
            case path, entries
            case omittedCount = "omitted_count"
        }
    }

    typealias Context = Void
    static let definition = ToolDefinition(
        name: "list_directory",
        description: "列出本地目录内容。路径必须是绝对路径；省略时使用应用当前工作目录。",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("要列出的绝对目录路径")
                ])
            ]),
            "additionalProperties": .bool(false)
        ])
    )

    func invoke(context: ToolContext<Void>, arguments: Arguments) async throws -> Output {
        try Task.checkCancellation()
        let path = CoreReadOnlyToolSupport.trimmed(arguments.path)
            ?? FileManager.default.currentDirectoryPath
        guard await CoreReadOnlyToolSupport.canRead(path) else {
            throw CoreReadOnlyToolSupport.denied(path, toolName: Self.definition.name)
        }
        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
            try Task.checkCancellation()
            let limited = Array(entries.prefix(500))
            return Output(path: path, entries: limited, omittedCount: entries.count - limited.count)
        } catch is CancellationError {
            throw AgentError.cancelled
        } catch {
            throw AgentError.toolExecutionFailed(
                toolName: Self.definition.name,
                detail: error.localizedDescription
            )
        }
    }
}

struct ReadFileAgentTool: AgentTool {
    struct Arguments: Codable, Sendable { let path: String }
    struct Output: Codable, Sendable {
        let path: String
        let content: String
        let truncated: Bool
    }

    typealias Context = Void
    static let definition = ToolDefinition(
        name: "read_file",
        description: "读取 UTF-8 文本文件。路径必须是绝对路径；单次最多返回 100000 个字符。",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("文件的绝对路径")
                ])
            ]),
            "required": .array([.string("path")]),
            "additionalProperties": .bool(false)
        ])
    )

    func invoke(context: ToolContext<Void>, arguments: Arguments) async throws -> Output {
        try Task.checkCancellation()
        let path = arguments.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw AgentError.invalidToolArguments(toolName: Self.definition.name, detail: "path 不能为空")
        }
        guard await CoreReadOnlyToolSupport.canRead(path) else {
            throw CoreReadOnlyToolSupport.denied(path, toolName: Self.definition.name)
        }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            try Task.checkCancellation()
            let limit = 100_000
            return Output(
                path: path,
                content: content.count > limit ? String(content.prefix(limit)) : content,
                truncated: content.count > limit
            )
        } catch is CancellationError {
            throw AgentError.cancelled
        } catch {
            throw AgentError.toolExecutionFailed(
                toolName: Self.definition.name,
                detail: error.localizedDescription
            )
        }
    }
}

struct SearchFilesAgentTool: AgentTool {
    struct Arguments: Codable, Sendable {
        let query: String
        let directory: String?
        let fileExtension: String?
        let limit: Int?

        enum CodingKeys: String, CodingKey {
            case query, directory, limit
            case fileExtension = "file_extension"
        }
    }

    struct Result: Codable, Sendable {
        let name: String
        let path: String
        let isDirectory: Bool
        let modifiedAt: String?
        let sizeBytes: Int?

        enum CodingKeys: String, CodingKey {
            case name, path
            case isDirectory = "is_directory"
            case modifiedAt = "modified_at"
            case sizeBytes = "size_bytes"
        }
    }

    struct Output: Codable, Sendable {
        let query: String
        let count: Int
        let searchMethod: String
        let results: [Result]

        enum CodingKeys: String, CodingKey {
            case query, count, results
            case searchMethod = "search_method"
        }
    }

    typealias Context = Void
    static let definition = ToolDefinition(
        name: "search_files",
        description: "使用 macOS Spotlight 按文件名或已索引内容搜索本机文件。用户说‘帮我找文件’时优先使用。",
        parameters: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "directory": .object(["type": .string("string")]),
                "file_extension": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")])
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false)
        ])
    )

    func invoke(context: ToolContext<Void>, arguments: Arguments) async throws -> Output {
        try Task.checkCancellation()
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw AgentError.invalidToolArguments(toolName: Self.definition.name, detail: "query 不能为空")
        }
        var directory = CoreReadOnlyToolSupport.trimmed(arguments.directory)
        let authorization = await MainActor.run {
            (
                AgentFileAccessStore.shared.requiresAuthorization,
                AgentFileAccessStore.shared.authorizedDirectories
            )
        }
        if authorization.0, directory == nil {
            guard authorization.1.count == 1 else {
                let detail = authorization.1.isEmpty
                    ? "尚未授权任何目录"
                    : "请指定以下已授权目录之一：\n" + authorization.1.joined(separator: "\n")
                throw AgentError.toolExecutionFailed(toolName: Self.definition.name, detail: detail)
            }
            directory = authorization.1[0]
        }
        if let directory {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw AgentError.toolExecutionFailed(
                    toolName: Self.definition.name,
                    detail: "搜索目录不存在或不是目录：\(directory)"
                )
            }
            guard await CoreReadOnlyToolSupport.canRead(directory) else {
                throw CoreReadOnlyToolSupport.denied(directory, toolName: Self.definition.name)
            }
        }

        let limit = min(max(arguments.limit ?? 20, 1), 100)
        let fileExtension = CoreReadOnlyToolSupport.trimmed(arguments.fileExtension)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            var processArguments: [String] = []
            if let directory { processArguments += ["-onlyin", directory] }
            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            processArguments.append("(kMDItemFSName == \"*\(escaped)*\"cd || kMDItemTextContent == \"*\(escaped)*\"cd)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = processArguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() }
            catch {
                throw AgentError.toolExecutionFailed(
                    toolName: Self.definition.name,
                    detail: error.localizedDescription
                )
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try Task.checkCancellation()
            let text = String(data: data, encoding: .utf8) ?? ""
            var paths = text.split(separator: "\n").map(String.init).filter { path in
                guard let fileExtension, !fileExtension.isEmpty else { return true }
                return URL(fileURLWithPath: path).pathExtension.lowercased() == fileExtension
            }

            if paths.count < limit {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let roots = directory.map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? [
                    home.appendingPathComponent("Desktop", isDirectory: true),
                    home.appendingPathComponent("Documents", isDirectory: true),
                    home.appendingPathComponent("Downloads", isDirectory: true)
                ]
                var seen = Set(paths)
                let normalized = query.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                for root in roots where paths.count < limit {
                    try Task.checkCancellation()
                    guard let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }
                    while let url = enumerator.nextObject() as? URL, paths.count < limit {
                        try Task.checkCancellation()
                        if let fileExtension, !fileExtension.isEmpty,
                           url.pathExtension.lowercased() != fileExtension { continue }
                        let name = url.lastPathComponent.folding(
                            options: [.caseInsensitive, .diacriticInsensitive],
                            locale: .current
                        )
                        if name.contains(normalized), seen.insert(url.path).inserted {
                            paths.append(url.path)
                        }
                    }
                }
            }

            let formatter = ISO8601DateFormatter()
            let results = Array(paths.prefix(limit)).map { path in
                let url = URL(fileURLWithPath: path)
                let values = try? url.resourceValues(forKeys: [
                    .contentModificationDateKey, .fileSizeKey, .isDirectoryKey
                ])
                return Result(
                    name: url.lastPathComponent,
                    path: path,
                    isDirectory: values?.isDirectory ?? false,
                    modifiedAt: values?.contentModificationDate.map(formatter.string(from:)),
                    sizeBytes: values?.fileSize
                )
            }
            if process.terminationStatus != 0, results.isEmpty {
                throw AgentError.toolExecutionFailed(
                    toolName: Self.definition.name,
                    detail: text.isEmpty ? "mdfind 返回错误" : text
                )
            }
            return Output(
                query: query,
                count: results.count,
                searchMethod: "spotlight_with_filename_fallback",
                results: results
            )
        }.value
    }
}
