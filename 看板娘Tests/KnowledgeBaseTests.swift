import Foundation
import Testing
@testable import 看板娘

struct KnowledgeBaseTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowledgeBaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func indexAndKnowledgeDataStayInSelectedDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let name = try KnowledgeBaseDiskStore.initializeIfNeeded(at: directory, name: "项目知识库")
        let reference = KnowledgeBaseReference(name: name, path: directory.path)
        let document = try KnowledgeBaseEngine.add(
            text: "发布流程要求先运行单元测试，再进行代码审查，最后发布。",
            title: "发布规范",
            source: "manual:release-policy",
            to: reference
        )

        #expect(FileManager.default.fileExists(
            atPath: KnowledgeBaseDiskStore.indexURL(for: directory).path
        ))
        #expect(document.chunks.count == 1)

        let stored = try KnowledgeBaseDiskStore.load(from: directory)
        #expect(stored.name == "项目知识库")
        #expect(stored.documents.count == 1)
        #expect(stored.documents[0].title == "发布规范")

        let results = try KnowledgeBaseEngine.search(
            query: "发布前要做什么测试",
            in: [reference],
            limit: 5
        )
        #expect(results.first?.title == "发布规范")
        #expect(results.first?.source == "manual:release-policy")
        #expect(results.first?.text.contains("单元测试") == true)
    }

    @Test
    func addingTheSameSourceUpdatesInsteadOfDuplicating() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try KnowledgeBaseDiskStore.initializeIfNeeded(at: directory, name: "团队知识")
        let reference = KnowledgeBaseReference(name: "团队知识", path: directory.path)

        let first = try KnowledgeBaseEngine.add(
            text: "旧的客服电话是 1000。",
            title: "联系方式",
            source: "/docs/contact.md",
            to: reference
        )
        let updated = try KnowledgeBaseEngine.add(
            text: "新的客服电话是 2000。",
            title: "联系方式",
            source: "/docs/contact.md",
            to: reference
        )

        let stored = try KnowledgeBaseDiskStore.load(from: directory)
        #expect(stored.documents.count == 1)
        #expect(first.id == updated.id)
        #expect(stored.documents[0].chunks[0].text.contains("2000"))
    }

    @Test @MainActor
    func registrySupportsMultipleExternalDirectoriesWithoutDeletingTheirData() throws {
        let suite = "KnowledgeBaseRegistryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let registry = KnowledgeBaseRegistry(defaults: defaults)
        let firstReference = try registry.registerDirectory(first, name: "产品")
        _ = try registry.registerDirectory(second, name: "技术")
        #expect(registry.enabledReferences.count == 2)
        #expect(throws: KnowledgeBaseError.self) {
            _ = try registry.writeTarget(identifier: nil)
        }
        #expect(try registry.writeTarget(identifier: "产品").path == first.path)

        registry.removeReference(firstReference.id)
        #expect(registry.references.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: KnowledgeBaseDiskStore.indexURL(for: first).path
        ))
    }

    @Test @MainActor
    func standardRegistryExposesKnowledgeBaseTools() {
        let names = Set(AgentToolRegistry.standard().definitions.map(\.name))
        #expect(names.contains("list_knowledge_bases"))
        #expect(names.contains("add_to_knowledge_base"))
        #expect(names.contains("search_knowledge_base"))
    }
}
