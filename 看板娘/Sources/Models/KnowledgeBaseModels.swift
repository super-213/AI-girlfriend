//
//  KnowledgeBaseModels.swift
//  看板娘
//
//  External, user-selected RAG knowledge bases. Only directory references are
//  kept in UserDefaults; document text, chunks and vectors stay in that folder.
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage

struct KnowledgeBaseReference: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let path: String
    var isEnabled: Bool
    let addedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isEnabled: Bool = true,
        addedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.path = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        self.isEnabled = isEnabled
        self.addedAt = addedAt
    }
}

enum KnowledgeBaseError: LocalizedError {
    case directoryMissing(String)
    case notDirectory(String)
    case noKnowledgeBase
    case ambiguousKnowledgeBase
    case knowledgeBaseNotFound(String)
    case emptyContent
    case unsupportedDocument(String)
    case corruptIndex(String)

    var errorDescription: String? {
        switch self {
        case .directoryMissing(let path): return "目录不存在：\(path)"
        case .notDirectory(let path): return "路径不是目录：\(path)"
        case .noKnowledgeBase: return "尚未配置已启用的知识库，请先在偏好设置 → 知识库中添加目录。"
        case .ambiguousKnowledgeBase: return "已启用多个知识库，请通过 knowledge_base 指定名称或目录路径。"
        case .knowledgeBaseNotFound(let value): return "未找到已启用的知识库：\(value)"
        case .emptyContent: return "没有可写入知识库的文本。"
        case .unsupportedDocument(let path): return "无法从文档提取文本：\(path)"
        case .corruptIndex(let path): return "知识库索引无法解析：\(path)"
        }
    }
}

@MainActor
final class KnowledgeBaseRegistry: ObservableObject {
    static let shared = KnowledgeBaseRegistry()
    static let storageKey = "agent.knowledgeBases.v1"

    @Published private(set) var references: [KnowledgeBaseReference]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([KnowledgeBaseReference].self, from: data) {
            references = decoded
        } else {
            references = []
        }
        references = references.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var enabledReferences: [KnowledgeBaseReference] {
        references.filter(\.isEnabled)
    }

    var hasEnabledKnowledgeBase: Bool { !enabledReferences.isEmpty }

    @discardableResult
    func registerDirectory(_ url: URL, name: String? = nil) throws -> KnowledgeBaseReference {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw KnowledgeBaseError.directoryMissing(standardized.path)
        }
        guard isDirectory.boolValue else { throw KnowledgeBaseError.notDirectory(standardized.path) }

        if let existing = references.first(where: { $0.path == standardized.path }) {
            return existing
        }

        let requestedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = standardized.lastPathComponent.isEmpty ? standardized.path : standardized.lastPathComponent
        let indexName = try KnowledgeBaseDiskStore.initializeIfNeeded(
            at: standardized,
            name: requestedName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
        )
        let reference = KnowledgeBaseReference(name: indexName, path: standardized.path)
        references.append(reference)
        references.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        AgentFileAccessStore.shared.addAuthorizedDirectory(standardized)
        persist()
        return reference
    }

    func setEnabled(_ id: UUID, enabled: Bool) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        references[index].isEnabled = enabled
        persist()
    }

    /// Removes only the app-side reference. The external index is intentionally preserved.
    func removeReference(_ id: UUID) {
        references.removeAll { $0.id == id }
        persist()
    }

    func writeTarget(identifier: String?) throws -> KnowledgeBaseReference {
        let enabled = enabledReferences
        guard !enabled.isEmpty else { throw KnowledgeBaseError.noKnowledgeBase }
        if let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty {
            guard let match = enabled.first(where: {
                $0.name.caseInsensitiveCompare(identifier) == .orderedSame
                    || $0.path == URL(fileURLWithPath: identifier, isDirectory: true).standardizedFileURL.path
                    || $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame
            }) else { throw KnowledgeBaseError.knowledgeBaseNotFound(identifier) }
            return match
        }
        guard enabled.count == 1, let only = enabled.first else {
            throw KnowledgeBaseError.ambiguousKnowledgeBase
        }
        return only
    }

    func searchTargets(identifier: String?) throws -> [KnowledgeBaseReference] {
        let enabled = enabledReferences
        guard !enabled.isEmpty else { throw KnowledgeBaseError.noKnowledgeBase }
        guard let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty else {
            return enabled
        }
        return [try writeTarget(identifier: identifier)]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(references) {
            defaults.set(data, forKey: Self.storageKey)
        }
        NotificationCenter.default.post(name: .knowledgeBaseConfigurationDidChange, object: nil)
    }
}

extension Notification.Name {
    static let knowledgeBaseConfigurationDidChange = Notification.Name("knowledgeBaseConfigurationDidChange")
}

struct KnowledgeBaseIndex: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var documents: [KnowledgeBaseDocument]
}

struct KnowledgeBaseDocument: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var source: String
    var contentHash: String
    var addedAt: Date
    var updatedAt: Date
    var chunks: [KnowledgeBaseChunk]
}

struct KnowledgeBaseChunk: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let ordinal: Int
    let text: String
    let embeddingLanguage: String?
    let embedding: [Double]?
}

struct KnowledgeSearchResult: Equatable, Sendable {
    let knowledgeBase: String
    let knowledgeBasePath: String
    let documentID: UUID
    let title: String
    let source: String
    let chunk: Int
    let text: String
    let score: Double
}

enum KnowledgeBaseDiskStore {
    static let storageDirectoryName = ".kanban-rag"
    static let indexFileName = "index.json"

    static func indexURL(for directory: URL) -> URL {
        directory
            .appendingPathComponent(storageDirectoryName, isDirectory: true)
            .appendingPathComponent(indexFileName, isDirectory: false)
    }

    @discardableResult
    static func initializeIfNeeded(at directory: URL, name: String) throws -> String {
        let indexURL = indexURL(for: directory)
        if FileManager.default.fileExists(atPath: indexURL.path) {
            return try load(from: directory).name
        }
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let now = Date()
        try save(
            KnowledgeBaseIndex(
                schemaVersion: 1,
                name: name,
                createdAt: now,
                updatedAt: now,
                documents: []
            ),
            to: directory
        )
        return name
    }

    static func load(from directory: URL) throws -> KnowledgeBaseIndex {
        let url = indexURL(for: directory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let index = try? decoder.decode(KnowledgeBaseIndex.self, from: data) else {
            throw KnowledgeBaseError.corruptIndex(url.path)
        }
        return index
    }

    static func save(_ index: KnowledgeBaseIndex, to directory: URL) throws {
        let url = indexURL(for: directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(index)
        try data.write(to: url, options: .atomic)
    }
}

enum KnowledgeBaseEngine {
    static let defaultChunkSize = 1_200
    static let defaultChunkOverlap = 180

    static func add(
        text: String,
        title: String,
        source: String,
        to reference: KnowledgeBaseReference
    ) throws -> KnowledgeBaseDocument {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { throw KnowledgeBaseError.emptyContent }
        let directory = URL(fileURLWithPath: reference.path, isDirectory: true)
        var index = try KnowledgeBaseDiskStore.load(from: directory)
        let hash = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        let now = Date()
        let existing = index.documents.first(where: { $0.source == source })
        let chunks = chunk(normalized).enumerated().map { offset, content in
            let vector = embedding(for: content)
            return KnowledgeBaseChunk(
                id: UUID(),
                ordinal: offset + 1,
                text: content,
                embeddingLanguage: vector?.language,
                embedding: vector?.values
            )
        }
        let document = KnowledgeBaseDocument(
            id: existing?.id ?? UUID(),
            title: title,
            source: source,
            contentHash: hash,
            addedAt: existing?.addedAt ?? now,
            updatedAt: now,
            chunks: chunks
        )
        index.documents.removeAll { $0.source == source }
        index.documents.append(document)
        index.updatedAt = now
        try KnowledgeBaseDiskStore.save(index, to: directory)
        return document
    }

    static func search(
        query: String,
        in references: [KnowledgeBaseReference],
        limit: Int
    ) throws -> [KnowledgeSearchResult] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { throw KnowledgeBaseError.emptyContent }
        let queryTokens = tokens(in: normalizedQuery)
        let queryVector = embedding(for: normalizedQuery)
        var results: [KnowledgeSearchResult] = []

        for reference in references {
            let directory = URL(fileURLWithPath: reference.path, isDirectory: true)
            let index = try KnowledgeBaseDiskStore.load(from: directory)
            for document in index.documents {
                for chunk in document.chunks {
                    let chunkTokens = tokens(in: chunk.text)
                    let lexical = lexicalScore(
                        query: normalizedQuery,
                        queryTokens: queryTokens,
                        text: chunk.text,
                        textTokens: chunkTokens
                    )
                    let semantic: Double?
                    if let queryVector,
                       queryVector.language == chunk.embeddingLanguage,
                       let stored = chunk.embedding,
                       stored.count == queryVector.values.count {
                        semantic = max(cosine(queryVector.values, stored), 0)
                    } else {
                        semantic = nil
                    }
                    let score = semantic.map { 0.68 * $0 + 0.32 * lexical } ?? lexical
                    guard score > 0 else { continue }
                    results.append(KnowledgeSearchResult(
                        knowledgeBase: index.name,
                        knowledgeBasePath: reference.path,
                        documentID: document.id,
                        title: document.title,
                        source: document.source,
                        chunk: chunk.ordinal,
                        text: chunk.text,
                        score: score
                    ))
                }
            }
        }
        return Array(results.sorted { lhs, rhs in
            if lhs.score == rhs.score { return lhs.title < rhs.title }
            return lhs.score > rhs.score
        }.prefix(max(1, min(limit, 20))))
    }

    static func chunk(_ text: String, size: Int = defaultChunkSize, overlap: Int = defaultChunkOverlap) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        let size = max(size, 200)
        let overlap = min(max(overlap, 0), size / 2)
        var chunks: [String] = []
        var start = normalized.startIndex

        while start < normalized.endIndex {
            let hardEnd = normalized.index(start, offsetBy: size, limitedBy: normalized.endIndex) ?? normalized.endIndex
            var end = hardEnd
            if hardEnd < normalized.endIndex {
                let searchStart = normalized.index(hardEnd, offsetBy: -min(180, normalized.distance(from: start, to: hardEnd)))
                let tail = normalized[searchStart..<hardEnd]
                if let boundary = tail.lastIndex(where: { "\n。！？.!?;；".contains($0) }) {
                    end = normalized.index(after: boundary)
                }
            }
            let value = String(normalized[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { chunks.append(value) }
            guard end < normalized.endIndex else { break }
            start = normalized.index(end, offsetBy: -min(overlap, normalized.distance(from: start, to: end)))
        }
        return chunks
    }

    private struct TextEmbedding {
        let language: String
        let values: [Double]
    }

    private static func embedding(for text: String) -> TextEmbedding? {
        let language = NLLanguageRecognizer.dominantLanguage(for: text) ?? .english
        guard let model = NLEmbedding.sentenceEmbedding(for: language),
              let vector = model.vector(for: text), !vector.isEmpty else { return nil }
        return TextEmbedding(language: language.rawValue, values: vector)
    }

    private static func tokens(in text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = folded
        if let language = NLLanguageRecognizer.dominantLanguage(for: folded) {
            tokenizer.setLanguage(language)
        }
        var values: [String] = []
        tokenizer.enumerateTokens(in: folded.startIndex..<folded.endIndex) { range, _ in
            let token = folded[range].trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            if !token.isEmpty { values.append(token) }
            return true
        }
        let cjk = folded.filter { scalar in
            scalar.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
        }
        if cjk.count >= 2 {
            var index = cjk.startIndex
            while let next = cjk.index(index, offsetBy: 2, limitedBy: cjk.endIndex) {
                values.append(String(cjk[index..<next]))
                guard next < cjk.endIndex else { break }
                index = cjk.index(after: index)
            }
        }
        return values
    }

    private static func lexicalScore(
        query: String,
        queryTokens: [String],
        text: String,
        textTokens: [String]
    ) -> Double {
        guard !queryTokens.isEmpty else { return 0 }
        let frequencies = Dictionary(textTokens.map { ($0, 1) }, uniquingKeysWith: +)
        let matched = queryTokens.reduce(0.0) { partial, token in
            partial + min(Double(frequencies[token] ?? 0), 3) / 3.0
        }
        var score = matched / Double(queryTokens.count)
        if text.localizedCaseInsensitiveContains(query) { score += 0.35 }
        return min(score, 1)
    }

    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0
        var leftNorm = 0.0
        var rightNorm = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            leftNorm += lhs[index] * lhs[index]
            rightNorm += rhs[index] * rhs[index]
        }
        guard leftNorm > 0, rightNorm > 0 else { return 0 }
        return dot / (sqrt(leftNorm) * sqrt(rightNorm))
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum KnowledgeBaseAnswerSkill {
    static let name = "knowledge-base-answer"
    static let description = "检索用户配置的外置 RAG 知识库，基于可追溯的知识片段回答问题。"

    static let content = """
    ---
    name: knowledge-base-answer
    description: 检索用户配置的外置 RAG 知识库，基于可追溯的知识片段回答问题。
    ---

    # 知识库问答

    1. 先根据用户的真实问题调用 `search_knowledge_base`。默认不指定 `knowledge_base`，以便同时检索所有已启用知识库。
    2. 如果首次结果不足，改用更精确的同义词、专有名词或拆分后的子问题再检索一次。
    3. 只把检索结果当作知识依据，不得把未出现在证据中的细节写成已知事实。
    4. 回答时在相应结论后标注 `[KB名称 / 文档标题 / 片段N]`，保留来源路径，方便用户追溯。
    5. 如果检索结果为空或不足以支持结论，明确说明“当前知识库中没有足够依据”，并说明建议补充什么资料。
    6. 不要为了显得完整而引入模型记忆中未验证的事实。
    """
}
