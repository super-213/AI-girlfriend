//
//  KnowledgeBaseTools.swift
//  看板娘
//
//  Agent tools for writing to and retrieving from external RAG indexes.
//

import Foundation
import PDFKit
import Vision

@MainActor
final class ListKnowledgeBasesTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "list_knowledge_bases",
        description: "列出用户已配置的外置 RAG 知识库名称、目录和启用状态。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String { "列出知识库" }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let values = KnowledgeBaseRegistry.shared.references.map { reference in
            var documentCount = 0
            if let index = try? KnowledgeBaseDiskStore.load(
                from: URL(fileURLWithPath: reference.path, isDirectory: true)
            ) {
                documentCount = index.documents.count
            }
            return [
                "id": reference.id.uuidString,
                "name": reference.name,
                "path": reference.path,
                "enabled": reference.isEnabled,
                "document_count": documentCount
            ] as [String: Any]
        }
        completion(.success(KnowledgeToolJSON.encode(["knowledge_bases": values])))
    }
}

@MainActor
final class AddToKnowledgeBaseTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "add_to_knowledge_base",
        description: "把用户提供的文本或本机文档提取、分块并写入指定的外置 RAG 知识库。已有同一文档路径时会更新索引。",
        parameters: [
            "type": "object",
            "properties": [
                "knowledge_base": ["type": "string", "description": "知识库名称或绝对目录路径；只启用一个时可省略"],
                "text": ["type": "string", "description": "要写入的文本，与 document_path 二选一"],
                "document_path": ["type": "string", "description": "要提取并写入的本机文档绝对路径，与 text 二选一"],
                "title": ["type": "string", "description": "知识文档标题；省略时使用文件名或自动标题"],
                "source": ["type": "string", "description": "文本的来源标识或 URL，用于后续更新和追溯"]
            ],
            "anyOf": [["required": ["text"]], ["required": ["document_path"]]],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = true

    func approvalSummary(arguments: [String: Any]) -> String {
        let target = arguments["knowledge_base"] as? String ?? "当前知识库"
        if let path = arguments["document_path"] as? String {
            return "将文档 \(URL(fileURLWithPath: path).lastPathComponent) 索引到 \(target)"
        }
        return "将提供的文本索引到 \(target)"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        do {
            let reference = try KnowledgeBaseRegistry.shared.writeTarget(
                identifier: arguments["knowledge_base"] as? String
            )
            let explicitTitle = (arguments["title"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let explicitSource = (arguments["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let path = (arguments["document_path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                guard AgentFileAccessStore.shared.canRead(standardizedPath) else {
                    completion(.failure(AgentFileAccessStore.denialMessage(path: standardizedPath)))
                    return
                }
                let title = explicitTitle.flatMap { $0.isEmpty ? nil : $0 }
                    ?? URL(fileURLWithPath: standardizedPath).lastPathComponent
                let source = explicitSource.flatMap { $0.isEmpty ? nil : $0 } ?? standardizedPath
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let text = try KnowledgeDocumentExtractor.extract(path: standardizedPath)
                        let document = try KnowledgeBaseEngine.add(
                            text: text,
                            title: title,
                            source: source,
                            to: reference
                        )
                        Task { @MainActor in completion(.success(Self.resultJSON(document, reference: reference))) }
                    } catch {
                        Task { @MainActor in completion(.failure(error.localizedDescription)) }
                    }
                }
                return
            }

            guard let text = arguments["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw KnowledgeBaseError.emptyContent
            }
            let title = explicitTitle.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            let source = explicitSource.flatMap { $0.isEmpty ? nil : $0 } ?? "manual:\(UUID().uuidString)"
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let document = try KnowledgeBaseEngine.add(
                        text: text,
                        title: title,
                        source: source,
                        to: reference
                    )
                    Task { @MainActor in completion(.success(Self.resultJSON(document, reference: reference))) }
                } catch {
                    Task { @MainActor in completion(.failure(error.localizedDescription)) }
                }
            }
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }

    nonisolated private static func resultJSON(
        _ document: KnowledgeBaseDocument,
        reference: KnowledgeBaseReference
    ) -> String {
        KnowledgeToolJSON.encode([
            "knowledge_base": reference.name,
            "knowledge_base_path": reference.path,
            "document_id": document.id.uuidString,
            "title": document.title,
            "source": document.source,
            "chunk_count": document.chunks.count,
            "content_hash": document.contentHash
        ])
    }
}

@MainActor
final class SearchKnowledgeBaseTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "search_knowledge_base",
        description: "使用语义向量与关键词混合检索外置 RAG 知识库，返回可引用的文档片段和来源。",
        parameters: [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "要在知识库中检索的自然语言问题或关键词"],
                "knowledge_base": ["type": "string", "description": "可选的知识库名称或目录；省略时检索所有已启用知识库"],
                "limit": ["type": "integer", "description": "返回片段数，1 到 20，默认 6"]
            ],
            "required": ["query"],
            "additionalProperties": false
        ]
    )
    let requiresConfirmation = false

    func approvalSummary(arguments: [String: Any]) -> String {
        "检索知识库：\(arguments["query"] as? String ?? "")"
    }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        guard let query = (arguments["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            completion(.failure("缺少 query"))
            return
        }
        do {
            let references = try KnowledgeBaseRegistry.shared.searchTargets(
                identifier: arguments["knowledge_base"] as? String
            )
            let limit = min(max(arguments["limit"] as? Int ?? 6, 1), 20)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let results = try KnowledgeBaseEngine.search(query: query, in: references, limit: limit)
                    let values = results.map { result in
                        [
                            "knowledge_base": result.knowledgeBase,
                            "knowledge_base_path": result.knowledgeBasePath,
                            "document_id": result.documentID.uuidString,
                            "title": result.title,
                            "source": result.source,
                            "chunk": result.chunk,
                            "score": (result.score * 10_000).rounded() / 10_000,
                            "text": result.text
                        ] as [String: Any]
                    }
                    let payload = KnowledgeToolJSON.encode([
                        "query": query,
                        "count": values.count,
                        "results": values
                    ])
                    Task { @MainActor in completion(.success(payload)) }
                } catch {
                    Task { @MainActor in completion(.failure(error.localizedDescription)) }
                }
            }
        } catch {
            completion(.failure(error.localizedDescription))
        }
    }
}

enum KnowledgeDocumentExtractor {
    static func extract(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw KnowledgeBaseError.unsupportedDocument(path)
        }
        let ext = url.pathExtension.lowercased()
        let content: String
        switch ext {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw KnowledgeBaseError.unsupportedDocument(path) }
            content = (0..<document.pageCount).compactMap { page in
                document.page(at: page)?.string.map { "## 第 \(page + 1) 页\n\($0)" }
            }.joined(separator: "\n\n")
        case "docx", "xlsx", "pptx":
            guard let extracted = OfficeDocumentExtractor.extract(path: path, extension: ext) else {
                throw KnowledgeBaseError.unsupportedDocument(path)
            }
            content = extracted
        case "doc", "odt", "rtf", "rtfd", "html", "htm", "webarchive":
            content = try runTextUtil(path: path)
        case "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp":
            content = try recognizeText(in: url)
        default:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw KnowledgeBaseError.unsupportedDocument(path)
            }
            content = text
        }
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw KnowledgeBaseError.emptyContent }
        return normalized
    }

    private static func runTextUtil(path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", "--", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let result = String(data: data, encoding: .utf8) else {
            throw KnowledgeBaseError.unsupportedDocument(path)
        }
        return result
    }

    private static func recognizeText(in url: URL) throws -> String {
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

private enum KnowledgeToolJSON {
    static func encode(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }
}
