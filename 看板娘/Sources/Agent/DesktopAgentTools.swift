//
//  DesktopAgentTools.swift
//  看板娘
//
//  Structured macOS application and file tools used by the local desktop Agent.
//

import AppKit
import Foundation
import PDFKit
import Vision

struct LocalFileAttachment: Identifiable, Equatable, Codable {
    let id: UUID
    let path: String
    let displayName: String
    let isDirectory: Bool

    init(id: UUID = UUID(), url: URL, fileManager: FileManager = .default) {
        let standardizedURL = url.standardizedFileURL
        var isDirectoryValue: ObjCBool = false
        fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectoryValue)
        self.id = id
        path = standardizedURL.path
        displayName = standardizedURL.lastPathComponent.isEmpty
            ? standardizedURL.path
            : standardizedURL.lastPathComponent
        isDirectory = isDirectoryValue.boolValue
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"]
            .contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}

enum FileAttachmentPromptBuilder {
    static func prompt(userInstruction: String, attachments: [LocalFileAttachment]) -> String {
        guard !attachments.isEmpty else { return userInstruction }
        let list = attachments.enumerated().map { index, attachment in
            "\(index + 1). \(attachment.isDirectory ? "目录" : "文件")：\(attachment.displayName)\n   绝对路径：\(attachment.path)"
        }.joined(separator: "\n")
        return """
        用户已明确将以下本机项目拖入对话，并授权你为完成本轮任务读取它们：
        \(list)

        用户指令：
        \(userInstruction)

        请优先使用 read_document、get_file_info 或 list_directory 读取上述路径。不要猜测文件内容。
        如需要新建、覆盖、移动或复制文件，使用对应的受控工具并等待用户确认。
        """
    }
}

private enum DesktopToolJSON {
    static func encode(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }
}

private struct DirectProcessResult {
    let exitCode: Int32
    let output: String
}

private enum DirectProcessRunner {
    static func run(executable: String, arguments: [String]) -> DirectProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return DirectProcessResult(exitCode: 1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return DirectProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

@MainActor
final class OpenApplicationTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "open_application",
        description: "在用户 Mac 上按应用名称或 bundle identifier 查找并启动应用。用户要求打开软件时优先使用，不要通过 Shell 拼接 open 命令。",
        parameters: [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "应用显示名称，例如 Xcode 或 Safari"],
                "bundle_identifier": ["type": "string", "description": "可选的 bundle identifier，例如 com.apple.Safari"]
            ],
            "additionalProperties": false,
            "anyOf": [["required": ["name"]], ["required": ["bundle_identifier"]]]
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "打开应用 \(arguments["name"] as? String ?? arguments["bundle_identifier"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        if let bundleID = Self.trimmed(arguments["bundle_identifier"]),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            open(url, completion: completion)
            return
        }

        guard let name = Self.trimmed(arguments["name"]) else {
            completion(.failure("缺少应用名称或 bundle identifier"))
            return
        }
        let candidates = Self.findApplications(named: name)
        guard !candidates.isEmpty else {
            completion(.failure("未找到应用“\(name)”"))
            return
        }
        guard candidates.count == 1 else {
            let paths = candidates.prefix(8).map(\.path).joined(separator: "\n")
            completion(.failure("找到多个匹配应用，请用更精确的名称或 bundle identifier：\n\(paths)"))
            return
        }
        open(candidates[0], completion: completion)
    }

    private func open(
        _ url: URL,
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { application, error in
            Task { @MainActor in
                if let error {
                    completion(.failure("打开应用失败：\(error.localizedDescription)"))
                } else {
                    completion(.success("已打开 \(application?.localizedName ?? url.deletingPathExtension().lastPathComponent)"))
                }
            }
        }
    }

    private static func trimmed(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func findApplications(named rawName: String) -> [URL] {
        let target = rawName.lowercased()
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var exact: [URL] = []
        var prefix: [URL] = []
        var contains: [URL] = []
        var seen = Set<String>()

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                enumerator.skipDescendants()
                guard seen.insert(url.path).inserted else { continue }
                let candidate = url.deletingPathExtension().lastPathComponent.lowercased()
                if candidate == target {
                    exact.append(url)
                } else if candidate.hasPrefix(target) {
                    prefix.append(url)
                } else if candidate.contains(target) {
                    contains.append(url)
                }
            }
        }
        if !exact.isEmpty { return exact.sorted { $0.path < $1.path } }
        if !prefix.isEmpty { return prefix.sorted { $0.path < $1.path } }
        return contains.sorted { $0.path < $1.path }
    }
}

@MainActor
final class SearchFilesTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "search_files",
        description: "使用 macOS Spotlight 按文件名或已索引内容搜索本机文件。用户说‘帮我找文件’时优先使用。",
        parameters: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "文件名或内容关键词"],
                "directory": ["type": "string", "description": "可选的绝对搜索目录"],
                "file_extension": ["type": "string", "description": "可选的扩展名，如 pdf，不含句点"],
                "limit": ["type": "integer", "description": "返回数量，1 到 100，默认 20"]
            ],
            "required": ["query"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "搜索文件 \(arguments["query"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let rawQuery = arguments["query"] as? String else {
            completion(.failure("缺少 query"))
            return
        }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            completion(.failure("搜索关键词不能为空"))
            return
        }
        var directory = (arguments["directory"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let fileExtension = (arguments["file_extension"] as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        let limit = min(max(arguments["limit"] as? Int ?? 20, 1), 100)

        if AgentFileAccessStore.shared.requiresAuthorization, directory == nil {
            let authorized = AgentFileAccessStore.shared.authorizedDirectories
            if authorized.count == 1 {
                directory = authorized[0]
            } else {
                let detail = authorized.isEmpty ? "尚未授权任何目录" : "请在以下目录中选择一个：\n" + authorized.joined(separator: "\n")
                completion(.failure("已启用目录授权，搜索时需要指定一个已授权目录。\(detail)"))
                return
            }
        }

        if let directory, !directory.isEmpty {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                completion(.failure("搜索目录不存在或不是目录：\(directory)"))
                return
            }
            guard AgentFileAccessStore.shared.canRead(directory) else {
                completion(.failure(AgentFileAccessStore.denialMessage(path: directory)))
                return
            }
        }

        let resolvedDirectory = directory
        DispatchQueue.global(qos: .userInitiated).async {
            var processArguments: [String] = []
            if let directory = resolvedDirectory, !directory.isEmpty {
                processArguments += ["-onlyin", directory]
            }
            let escaped = query
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            processArguments.append("(kMDItemFSName == \"*\(escaped)*\"cd || kMDItemTextContent == \"*\(escaped)*\"cd)")
            let result = DirectProcessRunner.run(executable: "/usr/bin/mdfind", arguments: processArguments)
            var paths = result.output
                .split(separator: "\n")
                .map(String.init)
                .filter { path in
                    guard let fileExtension, !fileExtension.isEmpty else { return true }
                    return URL(fileURLWithPath: path).pathExtension.lowercased() == fileExtension
                }
            var seen = Set(paths)

            if paths.count < limit {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let fallbackRoots = resolvedDirectory.map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? [
                    home.appendingPathComponent("Desktop", isDirectory: true),
                    home.appendingPathComponent("Documents", isDirectory: true),
                    home.appendingPathComponent("Downloads", isDirectory: true)
                ]
                let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                for root in fallbackRoots where paths.count < limit && FileManager.default.fileExists(atPath: root.path) {
                    guard let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    ) else { continue }
                    while let url = enumerator.nextObject() as? URL, paths.count < limit {
                        if let fileExtension, !fileExtension.isEmpty,
                           url.pathExtension.lowercased() != fileExtension {
                            continue
                        }
                        let normalizedName = url.lastPathComponent.folding(
                            options: [.caseInsensitive, .diacriticInsensitive],
                            locale: .current
                        )
                        if normalizedName.contains(normalizedQuery), seen.insert(url.path).inserted {
                            paths.append(url.path)
                        }
                    }
                }
            }

            paths = Array(paths.prefix(limit))

            let formatter = ISO8601DateFormatter()
            let items: [[String: Any]] = paths.map { path in
                let url = URL(fileURLWithPath: path)
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
                var item: [String: Any] = [
                    "name": url.lastPathComponent,
                    "path": path,
                    "is_directory": values?.isDirectory ?? false
                ]
                if let date = values?.contentModificationDate {
                    item["modified_at"] = formatter.string(from: date)
                }
                if let size = values?.fileSize { item["size_bytes"] = size }
                return item
            }
            Task { @MainActor in
                if result.exitCode != 0, items.isEmpty {
                    completion(.failure("文件搜索失败：\(result.output)"))
                } else {
                    completion(.success(DesktopToolJSON.encode([
                        "query": query,
                        "count": items.count,
                        "search_method": "spotlight_with_filename_fallback",
                        "results": items
                    ])))
                }
            }
        }
    }
}

@MainActor
final class GetFileInfoTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "get_file_info",
        description: "读取本机文件或目录的名称、类型、大小和修改时间，不读取内容。",
        parameters: [
            "type": "object",
            "properties": ["path": ["type": "string", "description": "绝对路径"]],
            "required": ["path"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String { "查看文件信息" }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let path = absolutePath(arguments["path"]) else {
            completion(.failure("缺少有效的绝对路径"))
            return
        }
        guard AgentFileAccessStore.shared.canRead(path) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: path)))
            return
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            completion(.failure("文件不存在：\(path)"))
            return
        }
        do {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                .creationDateKey, .contentTypeKey, .isReadableKey, .isWritableKey
            ])
            var result: [String: Any] = [
                "name": url.lastPathComponent,
                "path": path,
                "is_directory": values.isDirectory ?? false,
                "is_readable": values.isReadable ?? false,
                "is_writable": values.isWritable ?? false
            ]
            if let size = values.fileSize { result["size_bytes"] = size }
            if let type = values.contentType?.identifier { result["content_type"] = type }
            let formatter = ISO8601DateFormatter()
            if let date = values.creationDate { result["created_at"] = formatter.string(from: date) }
            if let date = values.contentModificationDate { result["modified_at"] = formatter.string(from: date) }
            completion(.success(DesktopToolJSON.encode(result)))
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}

@MainActor
final class ReadDocumentTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "read_document",
        description: "读取并提取本机文档内容。支持文本、代码、Markdown、JSON、CSV、PDF、RTF、Word/OpenDocument 文档、常见图片 OCR，以及系统 Spotlight 可提取文字的其他文档；也可列出目录。用户拖入文件后优先使用。",
        parameters: [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "文件或目录的绝对路径"],
                "max_characters": ["type": "integer", "description": "最多返回字符数，1000 到 100000，默认 50000"]
            ],
            "required": ["path"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String {
        "读取文档 \(arguments["path"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let path = absolutePath(arguments["path"]) else {
            completion(.failure("缺少有效的绝对路径"))
            return
        }
        guard AgentFileAccessStore.shared.canRead(path) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: path)))
            return
        }
        let limit = min(max(arguments["max_characters"] as? Int ?? 50_000, 1_000), 100_000)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.read(path: path, limit: limit)
            Task { @MainActor in completion(result) }
        }
    }

    nonisolated private static func read(path: String, limit: Int) -> AgentToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .failure("文件不存在：\(path)")
        }
        if isDirectory.boolValue {
            do {
                let entries = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                ).prefix(500).map { item -> [String: Any] in
                    let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    return [
                        "name": item.lastPathComponent,
                        "path": item.path,
                        "is_directory": values?.isDirectory ?? false,
                        "size_bytes": values?.fileSize ?? 0
                    ]
                }
                return .success(DesktopToolJSON.encode(["path": path, "entries": entries]))
            } catch {
                return .failure("读取目录失败：\(error.localizedDescription)")
            }
        }

        let ext = url.pathExtension.lowercased()
        let content: String
        do {
            switch ext {
            case "pdf":
                guard let document = PDFDocument(url: url) else { return .failure("无法打开 PDF") }
                content = (0..<document.pageCount).compactMap { index in
                    document.page(at: index)?.string.map { "## 第 \(index + 1) 页\n\($0)" }
                }.joined(separator: "\n\n")
            case "docx", "xlsx", "pptx":
                guard let extracted = OfficeDocumentExtractor.extract(path: path, extension: ext), !extracted.isEmpty else {
                    return .failure("无法解析该 Office 文档的结构化内容")
                }
                content = extracted
            case "doc", "odt", "rtf", "rtfd", "html", "htm", "webarchive":
                let converted = DirectProcessRunner.run(
                    executable: "/usr/bin/textutil",
                    arguments: ["-convert", "txt", "-stdout", "--", path]
                )
                guard converted.exitCode == 0 else {
                    return .failure("文档文字提取失败：\(converted.output)")
                }
                content = converted.output
            case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp":
                content = try recognizeText(in: url)
            default:
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    content = text
                } else {
                    let metadata = DirectProcessRunner.run(
                        executable: "/usr/bin/mdls",
                        arguments: ["-raw", "-name", "kMDItemTextContent", path]
                    )
                    let extracted = metadata.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard metadata.exitCode == 0, extracted != "(null)", !extracted.isEmpty else {
                        return .failure("当前不支持提取该文件类型的文字内容：.\(ext.isEmpty ? "(无扩展名)" : ext)")
                    }
                    content = extracted
                }
            }
        } catch {
            return .failure("无法读取该文档：\(error.localizedDescription)")
        }
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .success("文件可读，但未提取到文字内容。")
        }
        let bounded = normalized.count > limit
            ? String(normalized.prefix(limit)) + "\n…内容已截断"
            : normalized
        return .success("文件：\(url.lastPathComponent)\n路径：\(path)\n\n\(bounded)")
    }

    nonisolated private static func recognizeText(in url: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: "\n")
    }
}

@MainActor
final class OpenFileTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "open_file",
        description: "使用 macOS 默认应用打开一个已确定的本机文件或目录。",
        parameters: pathParameters
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String { "打开 \(arguments["path"] as? String ?? "")" }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard let path = absolutePath(arguments["path"]), FileManager.default.fileExists(atPath: path) else {
            completion(.failure("文件不存在或路径无效"))
            return
        }
        guard AgentFileAccessStore.shared.canRead(path) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: path)))
            return
        }
        completion(NSWorkspace.shared.open(URL(fileURLWithPath: path))
            ? .success("已打开 \(path)")
            : .failure("无法打开 \(path)"))
    }
}

@MainActor
final class RevealInFinderTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "reveal_in_finder",
        description: "在 Finder 中显示并选中一个已确定的本机文件。",
        parameters: pathParameters
    )
    let requiresConfirmation = false
    func approvalSummary(arguments: [String: Any]) -> String { "在 Finder 中显示文件" }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard let path = absolutePath(arguments["path"]), FileManager.default.fileExists(atPath: path) else {
            completion(.failure("文件不存在或路径无效"))
            return
        }
        guard AgentFileAccessStore.shared.canRead(path) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: path)))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        completion(.success("已在 Finder 中显示 \(path)"))
    }
}

@MainActor
final class WriteTextFileTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "write_text_file",
        description: "新建或覆盖 UTF-8 文本文件。用于把分析或处理结果保存到用户指定位置；执行前始终需要用户确认。",
        parameters: [
            "type": "object",
            "properties": [
                "path": ["type": "string", "description": "目标绝对路径"],
                "content": ["type": "string", "description": "要写入的完整 UTF-8 文本"],
                "overwrite": ["type": "boolean", "description": "文件存在时是否覆盖，默认 false"]
            ],
            "required": ["path", "content"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String {
        guard let path = absolutePath(arguments["path"]),
              let content = arguments["content"] as? String else { return "写入文件" }
        let old = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return "写入文件 \(path)\n\n\(TextDiffPreview.make(old: old, new: content))"
    }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        guard let path = absolutePath(arguments["path"]), let content = arguments["content"] as? String else {
            completion(.failure("缺少有效的 path 或 content"))
            return
        }
        let overwrite = arguments["overwrite"] as? Bool ?? false
        if FileManager.default.fileExists(atPath: path), !overwrite {
            completion(.failure("目标已存在；如确实需要覆盖，请将 overwrite 设为 true"))
            return
        }
        let url = URL(fileURLWithPath: path)
        guard AgentFileAccessStore.shared.canWrite(path) else {
            completion(.failure(AgentFileAccessStore.denialMessage(path: url.deletingLastPathComponent().path)))
            return
        }
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else {
            completion(.failure("目标目录不存在"))
            return
        }
        do {
            let existed = FileManager.default.fileExists(atPath: path)
            let backupPath = existed ? try AgentFileUndoStore.shared.prepareBackup(for: path) : nil
            try Data(content.utf8).write(to: url, options: .atomic)
            AgentFileUndoStore.shared.push(
                kind: existed ? .restoreBackup : .removeCreated,
                originalPath: path,
                backupPath: backupPath,
                summary: "写入 \(url.lastPathComponent)"
            )
            completion(.success("已写入 \(path)，\(content.utf8.count) 字节"))
        } catch {
            completion(.failure("写入失败：\(error.localizedDescription)"))
        }
    }
}

@MainActor
final class CopyFileTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "copy_file",
        description: "复制本机文件或目录到新路径；执行前需要用户确认，且不覆盖已有目标。",
        parameters: sourceDestinationParameters
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String {
        "复制 \(arguments["source"] as? String ?? "") 到 \(arguments["destination"] as? String ?? "")"
    }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        performFileOperation(arguments: arguments, verb: "复制", undoKind: .removeCreated, operation: FileManager.default.copyItem, completion: completion)
    }
}

@MainActor
final class MoveFileTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "move_file",
        description: "移动或重命名本机文件或目录；执行前需要用户确认，且不覆盖已有目标。",
        parameters: sourceDestinationParameters
    )
    let requiresConfirmation = true
    func approvalSummary(arguments: [String: Any]) -> String {
        "移动 \(arguments["source"] as? String ?? "") 到 \(arguments["destination"] as? String ?? "")"
    }
    func execute(arguments: [String: Any], completion: @escaping @MainActor (AgentToolExecutionResult) -> Void) {
        performFileOperation(arguments: arguments, verb: "移动", undoKind: .moveBack, operation: FileManager.default.moveItem, completion: completion)
    }
}

@MainActor private let pathParameters: [String: Any] = [
    "type": "object",
    "properties": ["path": ["type": "string", "description": "绝对路径"]],
    "required": ["path"],
    "additionalProperties": false
]

@MainActor private let sourceDestinationParameters: [String: Any] = [
    "type": "object",
    "properties": [
        "source": ["type": "string", "description": "源绝对路径"],
        "destination": ["type": "string", "description": "目标绝对路径"]
    ],
    "required": ["source", "destination"],
    "additionalProperties": false
]

private func absolutePath(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let path = NSString(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
    guard path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: path).standardizedFileURL.path
}

@MainActor
private func performFileOperation(
    arguments: [String: Any],
    verb: String,
    undoKind: AgentUndoRecord.Kind,
    operation: (URL, URL) throws -> Void,
    completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
) {
    guard let source = absolutePath(arguments["source"]),
          let destination = absolutePath(arguments["destination"]) else {
        completion(.failure("缺少有效的源路径或目标路径"))
        return
    }
    guard FileManager.default.fileExists(atPath: source) else {
        completion(.failure("源项目不存在"))
        return
    }
    guard AgentFileAccessStore.shared.canRead(source) else {
        completion(.failure(AgentFileAccessStore.denialMessage(path: source)))
        return
    }
    guard AgentFileAccessStore.shared.canWrite(destination) else {
        completion(.failure(AgentFileAccessStore.denialMessage(path: URL(fileURLWithPath: destination).deletingLastPathComponent().path)))
        return
    }
    guard !FileManager.default.fileExists(atPath: destination) else {
        completion(.failure("目标已存在，为避免覆盖已停止操作"))
        return
    }
    do {
        try operation(URL(fileURLWithPath: source), URL(fileURLWithPath: destination))
        AgentFileUndoStore.shared.push(
            kind: undoKind,
            originalPath: undoKind == .moveBack ? source : destination,
            currentPath: undoKind == .moveBack ? destination : nil,
            summary: "\(verb) \(URL(fileURLWithPath: source).lastPathComponent)"
        )
        completion(.success("已\(verb)到 \(destination)"))
    } catch {
        completion(.failure("\(verb)失败：\(error.localizedDescription)"))
    }
}

private enum TextDiffPreview {
    static func make(old: String, new: String) -> String {
        guard old != new else { return "内容无变化" }
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lines = ["--- 当前", "+++ 将要写入"]
        for line in oldLines.prefix(18) { lines.append("- \(line)") }
        if oldLines.count > 18 { lines.append("… 已省略 \(oldLines.count - 18) 行") }
        for line in newLines.prefix(18) { lines.append("+ \(line)") }
        if newLines.count > 18 { lines.append("… 已省略 \(newLines.count - 18) 行") }
        return lines.joined(separator: "\n")
    }
}
