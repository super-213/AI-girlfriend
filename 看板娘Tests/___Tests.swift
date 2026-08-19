import Foundation
import AppKit
import SwiftUI
import Testing
@testable import 看板娘

struct AgentFoundationTests {
    @MainActor
    private final class FakeModelClient: AgentModelClient {
        var responses: [AgentModelResponse] = []
        private(set) var requests: [[AgentMessage]] = []
        private(set) var requestPurposes: [AgentRequestPurpose] = []

        func sendAgentStreamRequest(
            messages: [AgentMessage],
            tools: [AgentToolDefinition],
            purpose: AgentRequestPurpose,
            onReceive: @escaping @MainActor @Sendable (String) -> Void,
            onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
            onError: @escaping @MainActor @Sendable (Error) -> Void
        ) {
            requests.append(messages)
            requestPurposes.append(purpose)
            let response = responses.removeFirst()
            if !response.content.isEmpty { onReceive(response.content) }
            onComplete(response)
        }

        func cancelStreamRequest() {}
    }

    @MainActor
    private final class EchoTool: AgentTool {
        let definition = AgentToolDefinition(
            name: "echo",
            description: "echo test",
            parameters: ["type": "object", "properties": [:]]
        )
        let requiresConfirmation = false
        func approvalSummary(arguments: [String: Any]) -> String { "echo" }
        func execute(
            arguments: [String: Any],
            completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
        ) {
            completion(.success(arguments["value"] as? String ?? ""))
        }
    }

    @MainActor
    private final class TestReadSkillTool: AgentTool {
        let definition = AgentToolDefinition(
            name: "read_skill",
            description: "read skill test",
            parameters: ["type": "object", "properties": [:]]
        )
        let requiresConfirmation = false
        func approvalSummary(arguments: [String: Any]) -> String { "read skill" }
        func execute(
            arguments: [String: Any],
            completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
        ) {
            completion(.success("skill:\(arguments["name"] as? String ?? "")"))
        }
    }

    @Test
    func toolCallArgumentsAndOpenAIMessageEncodingRoundTrip() throws {
        let call = AgentToolCall(
            id: "call-1",
            name: "read_file",
            arguments: #"{"path":"/tmp/example.txt"}"#
        )
        let arguments = try call.decodedArguments()
        #expect(arguments["path"] as? String == "/tmp/example.txt")

        let message = AgentMessage.assistant(content: nil, toolCalls: [call]).jsonObject()
        let encodedCalls = message["tool_calls"] as? [[String: Any]]
        let function = encodedCalls?.first?["function"] as? [String: Any]
        #expect(message["role"] as? String == "assistant")
        #expect(function?["name"] as? String == "read_file")
        #expect(function?["arguments"] as? String == call.arguments)
    }

    @Test
    func toolResultUsesStructuredSuccessEnvelope() throws {
        let success = AgentToolExecutionResult.success("星期一")
        let data = try #require(success.modelContent.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["ok"] as? Bool == true)
        #expect(object["result"] as? String == "星期一")
    }

    @Test @MainActor
    func standardRegistryExposesCoreAndAppTools() {
        let names = Set(AgentToolRegistry.standard().definitions.map(\.name))
        #expect(names.contains("get_current_datetime"))
        #expect(names.contains("read_skill"))
        #expect(names.contains("read_file"))
        #expect(names.contains("run_command"))
        #expect(names.contains("switch_pet_character"))
        #expect(names.contains("run_automation"))
    }

    @Test @MainActor
    func runtimeFeedsToolObservationBackAndContinuesUntilFinalAnswer() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(
                content: "",
                toolCalls: [
                    AgentToolCall(id: "call-echo", name: "echo", arguments: #"{"value":"ok"}"#)
                ]
            ),
            AgentModelResponse(content: "完成", toolCalls: [])
        ]
        let registry = AgentToolRegistry()
        registry.register(EchoTool())
        let runtime = AgentRuntime(
            apiManager: client,
            registry: registry,
            systemPromptProvider: { "system" }
        )
        var completed = false
        runtime.onCompleted = { completed = true }

        runtime.send("test")

        #expect(completed)
        #expect(client.requests.count == 2)
        #expect(client.requests[0].first?.content == client.requests[1].first?.content)
        #expect(client.requests[0].first?.content?.contains("当前本地时间") == false)
        #expect(client.requests[0].first?.content?.contains("get_current_datetime") == true)
        #expect(client.requests[1].last?.role == .tool)
        #expect(client.requests[1].last?.content?.contains("ok") == true)
        #expect(runtime.messages.last?.content == "完成")
    }

    @Test @MainActor
    func runtimeRewritesAnEnabledSkillNameMistakenForATool() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(
                content: "",
                toolCalls: [
                    AgentToolCall(id: "call-weather", name: "weather", arguments: #"{"location":"上海"}"#)
                ]
            ),
            AgentModelResponse(content: "上海天气结果", toolCalls: [])
        ]
        let registry = AgentToolRegistry()
        registry.register(TestReadSkillTool())
        let runtime = AgentRuntime(
            apiManager: client,
            registry: registry,
            enabledSkillNameResolver: { $0.caseInsensitiveCompare("weather") == .orderedSame ? "weather" : nil },
            systemPromptProvider: { "system" }
        )
        var exposedToolNames: [String] = []
        runtime.onToolStarted = { exposedToolNames.append($0) }

        runtime.send("上海今天天气怎么样")

        #expect(client.requests.count == 2)
        #expect(exposedToolNames == ["read_skill"])
        #expect(runtime.messages[2].toolCalls?.first?.name == "read_skill")
        #expect(runtime.messages[3].name == "read_skill")
        #expect(runtime.messages[3].content?.contains("skill:weather") == true)
        #expect(runtime.messages.last?.content == "上海天气结果")
    }

    @Test @MainActor
    func runtimeDoesNotRewriteAnUnknownUnregisteredTool() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(
                content: "",
                toolCalls: [AgentToolCall(id: "call-unknown", name: "weather", arguments: "{}")]
            ),
            AgentModelResponse(content: "已根据错误恢复", toolCalls: [])
        ]
        let registry = AgentToolRegistry()
        registry.register(TestReadSkillTool())
        let runtime = AgentRuntime(
            apiManager: client,
            registry: registry,
            enabledSkillNameResolver: { _ in nil },
            systemPromptProvider: { "system" }
        )

        runtime.send("test")

        #expect(runtime.messages[2].toolCalls?.first?.name == "weather")
        #expect(runtime.messages[3].name == "weather")
        #expect(runtime.messages[3].content?.contains("未注册的工具") == true)
    }

    @Test @MainActor
    func startingNewConversationDropsPreviousTurnContext() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(content: "first", toolCalls: []),
            AgentModelResponse(content: "second", toolCalls: [])
        ]
        let runtime = AgentRuntime(
            apiManager: client,
            registry: AgentToolRegistry(),
            systemPromptProvider: { "system" }
        )

        runtime.send("one")
        runtime.startNewConversation()
        runtime.send("two")

        #expect(client.requests.count == 2)
        #expect(client.requests[1].count == 2)
        #expect(client.requests[1][0].role == .system)
        #expect(client.requests[1][1] == .user("two"))
    }

    @Test @MainActor
    func runtimeCompactsOlderTurnsIntoAStructuredSummary() {
        let client = FakeModelClient()
        client.responses = [
            AgentModelResponse(content: String(repeating: "旧回复", count: 160), toolCalls: []),
            AgentModelResponse(
                content: "## 用户目标与约束\n- 继续测试\n\n## 当前状态与未完成项\n- 等待新问题",
                toolCalls: []
            ),
            AgentModelResponse(content: "新回复", toolCalls: [])
        ]
        let runtime = AgentRuntime(
            apiManager: client,
            registry: AgentToolRegistry(),
            contextCompactionPolicy: AgentContextCompactionPolicy(
                triggerTokenCount: 120,
                targetTokenCount: 80,
                summaryTokenReserve: 20,
                maximumToolResultCharacters: 200,
                maximumSummaryInputCharacters: 4_000
            ),
            systemPromptProvider: { "system" }
        )
        var events: [AgentContextCompactionEvent] = []
        runtime.onContextCompacted = { events.append($0) }

        runtime.send("第一个问题")
        runtime.send("第二个问题")

        #expect(client.requestPurposes == [.conversation, .contextCompaction, .conversation])
        #expect(events.count == 1)
        #expect(client.requests[1].first?.content?.contains("Agent 会话压缩器") == true)
        #expect(client.requests[2].contains(where: { $0.contextKind == .compactionSummary }))
        #expect(client.requests[2].last == .user("第二个问题"))
        #expect(client.requests[2].contains(where: { $0.content?.contains("第一个问题") == true }) == false)
        #expect(runtime.messages.last?.content == "新回复")
    }

    @Test
    func compactionPlannerKeepsToolCallAndResultInTheSameRecentTurn() throws {
        let manager = AgentContextManager(policy: AgentContextCompactionPolicy(
            triggerTokenCount: 1,
            targetTokenCount: 1,
            summaryTokenReserve: 1,
            maximumToolResultCharacters: 200,
            maximumSummaryInputCharacters: 4_000
        ))
        let call = AgentToolCall(id: "call-1", name: "read_file", arguments: "{}")
        let messages: [AgentMessage] = [
            .system("system"),
            .user("旧问题"),
            .assistant(content: "旧回复"),
            .user("新问题"),
            .assistant(content: nil, toolCalls: [call]),
            .tool(call: call, content: "工具结果")
        ]

        let plan = try #require(manager.makePlan(messages: messages, tools: []))

        #expect(plan.messagesToSummarize == Array(messages[1...2]))
        #expect(plan.recentMessages == Array(messages[3...5]))
    }

    @Test
    func compactionSummaryMetadataSurvivesPersistence() throws {
        let original = AgentMessage.contextSummary("## 当前状态与未完成项\n- 继续实现")

        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(AgentMessage.self, from: encoded)

        #expect(restored == original)
        #expect(restored.contextKind == .compactionSummary)
    }

    @Test
    func longToolResultsKeepTheirBeginningAndEndWithinTheContextLimit() {
        let manager = AgentContextManager(policy: AgentContextCompactionPolicy(
            triggerTokenCount: 100,
            targetTokenCount: 50,
            summaryTokenReserve: 10,
            maximumToolResultCharacters: 20,
            maximumSummaryInputCharacters: 100
        ))
        let bounded = manager.boundedToolResult("BEGIN-1234567890-abcdefghij-END")

        #expect(bounded.hasPrefix("BEGIN"))
        #expect(bounded.hasSuffix("j-END"))
        #expect(bounded.contains("中部内容已省略"))
        #expect(bounded.count < 80)
    }

    @Test
    func parsesCacheUsageWithoutTreatingMissingCacheDataAsZero() throws {
        let qwenJSON: [String: Any] = [
            "usage": [
                "prompt_tokens": 1_000,
                "completion_tokens": 120,
                "total_tokens": 1_120,
                "prompt_tokens_details": [
                    "cached_tokens": 750,
                    "cache_creation_input_tokens": 100,
                    "cache_write_tokens": 50
                ]
            ]
        ]
        let qwenUsage = try #require(AgentTokenUsage(responseJSONObject: qwenJSON))
        #expect(qwenUsage.promptTokens == 1_000)
        #expect(qwenUsage.cachedTokens == 750)
        #expect(qwenUsage.cacheCreationTokens == 100)
        #expect(qwenUsage.cacheWriteTokens == 50)
        #expect(qwenUsage.cacheHitRatio == 0.75)

        let ollamaUsage = try #require(AgentTokenUsage(responseJSONObject: [
            "prompt_eval_count": 240,
            "eval_count": 60
        ]))
        #expect(ollamaUsage.promptTokens == 240)
        #expect(ollamaUsage.cachedTokens == nil)
        #expect(ollamaUsage.cacheHitRatio == nil)
    }

    @Test
    func persistsCumulativeCacheMetricsPerProviderAndModel() throws {
        let suiteName = "AgentCacheMetricsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let measured = try #require(AgentTokenUsage(responseJSONObject: [
            "usage": [
                "prompt_tokens": 1_000,
                "prompt_tokens_details": ["cached_tokens": 250]
            ]
        ]))
        let unmeasured = try #require(AgentTokenUsage(responseJSONObject: [
            "prompt_eval_count": 500
        ]))

        _ = AgentCacheMetricsStore.record(
            measured,
            provider: "qwen",
            model: "qwen-plus",
            defaults: defaults
        )
        let metrics = AgentCacheMetricsStore.record(
            unmeasured,
            provider: "qwen",
            model: "qwen-plus",
            defaults: defaults
        )

        #expect(metrics.requestCount == 2)
        #expect(metrics.measuredRequestCount == 1)
        #expect(metrics.promptTokens == 1_500)
        #expect(metrics.measuredPromptTokens == 1_000)
        #expect(metrics.cachedTokens == 250)
        #expect(metrics.cacheHitRatio == 0.25)
        #expect(
            AgentCacheMetricsStore.load(defaults: defaults)["qwen|qwen-plus"] == metrics
        )
    }

    @Test
    func dialogCacheStatusLoadsMetricsForTheActiveProviderAndModel() throws {
        let suiteName = "DialogCacheStatusTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("qwen", forKey: "provider")
        defaults.set("qwen-plus", forKey: "aiModel")

        let usage = try #require(AgentTokenUsage(responseJSONObject: [
            "usage": [
                "prompt_tokens": 800,
                "prompt_tokens_details": ["cached_tokens": 600]
            ]
        ]))
        _ = AgentCacheMetricsStore.record(
            usage,
            provider: "qwen",
            model: "qwen-plus",
            defaults: defaults
        )

        let status = DialogCacheStatus.load(from: defaults)

        #expect(status.provider == "qwen")
        #expect(status.model == "qwen-plus")
        #expect(status.cacheHitRatio == 0.75)
        #expect(status.metrics?.cachedTokens == 600)
    }
}

struct SkillManifestTests {
    @Test
    func parsesInlineAndFoldedFrontMatterValues() throws {
        let inline = try SkillManifestParser.parse("""
        ---
        name: weather
        description: 查询实时天气和降雨概率。
        ---

        # Weather
        """)
        #expect(inline == SkillManifest(name: "weather", description: "查询实时天气和降雨概率。"))

        let folded = try SkillManifestParser.parse("""
        ---
        name: travel-weather
        description: >
          查询天气、温度和降雨。
          用户询问出行或穿衣建议时使用。
        ---
        """)
        #expect(folded.description == "查询天气、温度和降雨。 用户询问出行或穿衣建议时使用。")
    }

    @Test
    func invalidManifestIsDisabledWithAValidationReason() {
        let record = SkillLibrary.makeRecord(
            fileURL: URL(fileURLWithPath: "/tmp/weather.md"),
            content: "# Weather"
        )

        #expect(!record.isEnabled)
        #expect(!record.isValid)
        #expect(record.validationError?.contains("front matter") == true)
    }

    @Test
    func oversizedCatalogDescriptionIsRejected() {
        let record = SkillLibrary.makeRecord(
            fileURL: URL(fileURLWithPath: "/tmp/weather.md"),
            content: """
            ---
            name: weather
            description: \(String(repeating: "天", count: 1_025))
            ---
            """
        )

        #expect(!record.isEnabled)
        #expect(record.validationError?.contains("1024") == true)
    }

    @Test
    func migratesLegacyRecordsAndBuildsOnlyEnabledValidCatalog() throws {
        let suiteName = "SkillManifestTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkillManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let weatherURL = directory.appendingPathComponent("legacy-weather.md")
        let musicURL = directory.appendingPathComponent("music.md")
        try """
        ---
        name: weather
        description: 查询实时天气。
        ---
        天气工作流。
        """.write(to: weatherURL, atomically: true, encoding: .utf8)
        try """
        ---
        name: music
        description: 播放音乐。
        ---
        音乐工作流。
        """.write(to: musicURL, atomically: true, encoding: .utf8)

        let legacyJSON: [[String: Any]] = [[
            "id": UUID().uuidString,
            "name": "legacy-weather.md",
            "path": weatherURL.path,
            "addedAt": Date().timeIntervalSinceReferenceDate
        ]]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        // JSONDecoder's default Date strategy expects seconds since reference date.
        defaults.set(legacyData, forKey: AgentSkillStorageKeys.skillFiles)

        let migrated = SkillLibrary.load(defaults: defaults)
        #expect(migrated.first?.name == "weather")
        #expect(migrated.first?.description == "查询实时天气。")
        #expect(migrated.first?.fileName == "legacy-weather.md")

        var disabled = SkillLibrary.makeRecord(
            fileURL: musicURL,
            content: try String(contentsOf: musicURL, encoding: .utf8)
        )
        disabled.isEnabled = false
        let records = migrated + [disabled]
        defaults.set(try JSONEncoder().encode(records), forKey: AgentSkillStorageKeys.skillFiles)

        #expect(SkillLibrary.enabledCatalog(defaults: defaults) == [[
            "name": "weather",
            "description": "查询实时天气。"
        ]])
        #expect(SkillLibrary.enabledSkill(named: "WEATHER", defaults: defaults)?.path == weatherURL.path)
        #expect(SkillLibrary.enabledSkill(named: "music", defaults: defaults) == nil)
    }

    @Test
    func duplicateManifestNamesAreDisabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuplicateSkillTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let content = """
        ---
        name: weather
        description: 查询天气。
        ---
        """
        let firstURL = directory.appendingPathComponent("first.md")
        let secondURL = directory.appendingPathComponent("second.md")
        try content.write(to: firstURL, atomically: true, encoding: .utf8)
        try content.write(to: secondURL, atomically: true, encoding: .utf8)

        let refreshed = SkillLibrary.refresh([
            SkillLibrary.makeRecord(fileURL: firstURL, content: content),
            SkillLibrary.makeRecord(fileURL: secondURL, content: content)
        ])

        #expect(refreshed.allSatisfy { !$0.isEnabled })
        #expect(refreshed.allSatisfy { $0.validationError?.contains("重复") == true })
    }

    @Test
    func importsStandardSkillDirectoryWithScriptsAndPersistsPackagePath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectorySkillImportTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("weather", isDirectory: true)
        let scripts = source.appendingPathComponent("scripts", isDirectory: true)
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let content = """
        ---
        name: weather
        description: 查询实时天气。
        ---

        运行 scripts/weather.sh。
        """
        try content.write(
            to: source.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/sh\necho sunny\n".write(
            to: scripts.appendingPathComponent("weather.sh"),
            atomically: true,
            encoding: .utf8
        )

        let imported = try SkillImporter.copyIntoLibrary(from: source, libraryDirectory: library)
        let packageURL = try #require(imported.packageURL)
        #expect(imported.entryURL == packageURL.appendingPathComponent("SKILL.md"))
        #expect(FileManager.default.fileExists(
            atPath: packageURL.appendingPathComponent("scripts/weather.sh").path
        ))

        let record = SkillLibrary.makeRecord(
            fileURL: imported.entryURL,
            packageURL: packageURL,
            content: try String(contentsOf: imported.entryURL, encoding: .utf8)
        )
        #expect(record.name == "weather")
        #expect(record.packagePath == packageURL.path)
        #expect(record.resourceBasePath == packageURL.path)

        let restored = try JSONDecoder().decode(
            SkillFile.self,
            from: JSONEncoder().encode(record)
        )
        #expect(restored == record)
    }

    @Test
    func rejectsDirectoryWithoutRootSkillManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvalidDirectorySkillTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("weather", isDirectory: true)
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try SkillImporter.copyIntoLibrary(from: source, libraryDirectory: library)
            Issue.record("缺少 SKILL.md 的目录不应导入成功")
        } catch let error as SkillImportError {
            #expect(error == .missingSkillManifest)
        }
    }

    @Test @MainActor
    func readSkillToolReturnsTheFullEnabledSkillInstructions() throws {
        let suiteName = "ReadSkillToolTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadSkillToolTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let skillURL = directory.appendingPathComponent("weather.md")
        let content = """
        ---
        name: weather
        description: 查询实时天气。
        ---

        必须先使用实时天气工具，再根据结果回答。
        """
        try content.write(to: skillURL, atomically: true, encoding: .utf8)
        let skill = SkillLibrary.makeRecord(fileURL: skillURL, content: content)
        defaults.set(try JSONEncoder().encode([skill]), forKey: AgentSkillStorageKeys.skillFiles)

        var result: AgentToolExecutionResult?
        ReadSkillTool(defaults: defaults).execute(arguments: ["name": "weather"]) {
            result = $0
        }

        #expect(result?.isError == false)
        #expect(result?.content.contains("Skill 资源根目录：\(directory.path)") == true)
        #expect(result?.content.contains(content) == true)
    }
}

struct StreamingTextCoalescerTests {
    @Test @MainActor
    func flushCombinesPendingFragmentsInOrder() {
        var updates: [String] = []
        let coalescer = StreamingTextCoalescer(interval: .seconds(10)) {
            updates.append($0)
        }

        coalescer.append("你")
        coalescer.append("好")
        #expect(updates.isEmpty)

        coalescer.flush()
        #expect(updates == ["你好"])
    }

    @Test @MainActor
    func resetDropsFragmentsFromThePreviousRequest() {
        var updates: [String] = []
        let coalescer = StreamingTextCoalescer(interval: .seconds(10)) {
            updates.append($0)
        }

        coalescer.append("旧请求")
        coalescer.reset()
        coalescer.append("新请求")
        coalescer.flush()

        #expect(updates == ["新请求"])
    }
}

struct ModelConfigurationLibraryTests {
    private final class MemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
        var values: [String: String] = [:]
        var writeError: Error?

        func apiKey(for configurationID: String) throws -> String? {
            values[configurationID]
        }

        func setAPIKey(_ apiKey: String, for configurationID: String) throws {
            if let writeError { throw writeError }
            values[configurationID] = apiKey
        }

        func removeAPIKey(for configurationID: String) throws {
            values.removeValue(forKey: configurationID)
        }
    }

    @Test
    func configurationRequiresAnHTTPServiceURL() {
        var configuration = ModelConfiguration.preset(for: .openAICompatible)
        #expect(configuration.isValid)

        configuration.apiUrl = "localhost:1234/v1/chat/completions"
        #expect(!configuration.isValid)

        configuration.apiUrl = "http://localhost:1234/v1/chat/completions"
        #expect(configuration.isValid)
    }

    @Test
    func legacyLMStudioConfigurationMigratesIntoNamedLibrary() throws {
        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacy = ModelConfiguration.migratedLegacy(
            provider: "qwen",
            aiModel: "local/qwen3",
            apiUrl: "http://localhost:1234/v1/chat/completions",
            apiKey: "lm-studio"
        )
        defaults.set("lm-studio", forKey: "apiKey")
        let keyStore = MemoryAPIKeyStore()
        let library = try ModelConfigurationLibrary.load(
            from: defaults,
            legacyConfiguration: legacy,
            keyStore: keyStore
        )

        #expect(library.configurations.count == 1)
        #expect(library.configurations[0].name == "LM Studio 本地")
        #expect(library.activeConfigurationID == library.configurations[0].id)
        #expect(defaults.data(forKey: ModelConfigurationLibrary.configurationsKey) != nil)
        #expect(defaults.object(forKey: "apiKey") == nil)
        #expect(keyStore.values[library.activeConfigurationID] == "lm-studio")
        let persisted = try #require(defaults.data(forKey: ModelConfigurationLibrary.configurationsKey))
        #expect(!String(decoding: persisted, as: UTF8.self).contains("lm-studio"))
        #expect(!String(decoding: persisted, as: UTF8.self).contains("apiKey"))
    }

    @Test
    func multipleCompatibleServicesRoundTripWithoutOverwritingEachOther() throws {
        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cloud = ModelConfiguration(
            name: "通义千问云端",
            provider: "qwen",
            aiModel: "qwen-plus",
            apiUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            apiKey: "cloud-key"
        )
        let local = ModelConfiguration(
            name: "LM Studio 本地",
            provider: "qwen",
            aiModel: "local/qwen3",
            apiUrl: "http://localhost:1234/v1/chat/completions",
            apiKey: "lm-studio"
        )
        let saved = ModelConfigurationLibrary(
            configurations: [cloud, local],
            activeConfigurationID: local.id
        )
        let keyStore = MemoryAPIKeyStore()
        try saved.save(to: defaults, keyStore: keyStore)

        let loaded = try ModelConfigurationLibrary.load(
            from: defaults,
            legacyConfiguration: cloud,
            keyStore: keyStore
        )
        #expect(loaded == saved)
        #expect(loaded.configurations[0].apiKey == "cloud-key")
        #expect(loaded.configurations[1].apiKey == "lm-studio")
    }

    @Test
    func externalSettingsPatchUpdatesOnlyTheActiveProfileDetails() throws {
        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cloud = ModelConfiguration.preset(for: .openAICompatible)
        var local = ModelConfiguration.preset(for: .openAICompatible)
        local.name = "LM Studio 本地"
        local.apiUrl = "http://localhost:1234/v1/chat/completions"
        let original = ModelConfigurationLibrary(
            configurations: [cloud, local],
            activeConfigurationID: local.id
        )
        let keyStore = MemoryAPIKeyStore()
        try original.save(to: defaults, keyStore: keyStore)

        let patched = ModelConfiguration.migratedLegacy(
            provider: "qwen",
            aiModel: "local/new-model",
            apiUrl: local.apiUrl,
            apiKey: "new-key"
        )
        try ModelConfigurationLibrary.synchronizeActiveConfiguration(
            in: defaults,
            legacyConfiguration: patched,
            keyStore: keyStore
        )

        let loaded = try ModelConfigurationLibrary.load(
            from: defaults,
            legacyConfiguration: cloud,
            keyStore: keyStore
        )
        #expect(loaded.configurations[0] == cloud)
        #expect(loaded.configurations[1].id == local.id)
        #expect(loaded.configurations[1].name == "LM Studio 本地")
        #expect(loaded.configurations[1].aiModel == "local/new-model")
        #expect(loaded.configurations[1].apiKey == "new-key")
    }

    @Test
    func failedKeychainMigrationKeepsLegacyPlaintextForRetry() throws {
        struct ExpectedFailure: Error {}

        let suiteName = "ModelConfigurationLibraryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("legacy-secret", forKey: "apiKey")

        let keyStore = MemoryAPIKeyStore()
        keyStore.writeError = ExpectedFailure()
        let legacy = ModelConfiguration.migratedLegacy(
            provider: "zhipu",
            aiModel: "glm-4v-flash",
            apiUrl: "https://example.com/chat/completions",
            apiKey: "legacy-secret"
        )

        #expect(throws: ExpectedFailure.self) {
            _ = try ModelConfigurationLibrary.load(
                from: defaults,
                legacyConfiguration: legacy,
                keyStore: keyStore
            )
        }
        #expect(defaults.string(forKey: "apiKey") == "legacy-secret")
    }

    @Test
    func settingsPatchEncodingRedactsAPIKey() throws {
        let patch = SettingsPatch(apiKey: "sk-super-secret-value")
        let encoded = try JSONEncoder().encode(patch)
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(!json.contains("sk-super-secret-value"))
        #expect(json.contains(SensitiveDataRedactor.placeholder))
    }

    @Test
    func redactorRemovesConfiguredAndBearerSecrets() {
        let secret = "otherwise-unrecognizable-secret"
        let message = "Authorization: Bearer \(secret); apiKey=sk-example-secret-123"
        let redacted = SensitiveDataRedactor.redact(message, secrets: [secret])

        #expect(!redacted.contains(secret))
        #expect(!redacted.contains("sk-example-secret-123"))
        #expect(redacted.contains(SensitiveDataRedactor.placeholder))
    }
}

struct PetHorizontalPositionTests {
    @Test
    func centerIsTheDefaultPosition() {
        #expect(PetHorizontalPosition.defaultValue == 0.5)
    }

    @Test
    func positionIsClampedAndPresentedAsAPercentage() {
        #expect(PetHorizontalPosition.clamped(-1) == 0)
        #expect(PetHorizontalPosition.clamped(0.375) == 0.375)
        #expect(PetHorizontalPosition.clamped(2) == 1)
        #expect(PetHorizontalPosition.percentage(for: 0.375) == 38)
    }

    @Test
    func contentMovesContinuouslyAcrossAvailableContainerWidth() {
        #expect(PetHorizontalPosition.leadingOffset(containerWidth: 200, contentWidth: 40, position: 0) == 0)
        #expect(PetHorizontalPosition.leadingOffset(containerWidth: 200, contentWidth: 40, position: 0.25) == 40)
        #expect(PetHorizontalPosition.leadingOffset(containerWidth: 200, contentWidth: 40, position: 0.5) == 80)
        #expect(PetHorizontalPosition.leadingOffset(containerWidth: 200, contentWidth: 40, position: 1) == 160)
    }

    @Test
    func legacyThreeStepValuesMigrateToContinuousPositions() throws {
        let suiteName = "PetHorizontalPositionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for (legacyValue, expectedValue) in [("left", 0.0), ("center", 0.5), ("right", 1.0)] {
            defaults.removeObject(forKey: PetHorizontalPosition.storageKey)
            defaults.set(legacyValue, forKey: PetHorizontalPosition.legacyStorageKey)

            PetHorizontalPosition.migrateStorage(in: defaults)

            #expect(defaults.double(forKey: PetHorizontalPosition.storageKey) == expectedValue)
        }
    }

    @Test
    func alignmentUsesTheVisibleArtworkBoundsInsteadOfTheTransparentCanvas() {
        let bounds = PetArtworkBounds(
            sourceSize: CGSize(width: 360, height: 534),
            visibleMinX: 94,
            visibleMaxX: 280
        )

        let left = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            position: 0
        )
        let center = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            position: 0.5
        )
        let right = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            position: 1
        )
        let quarter = PetArtworkAlignmentGeometry.horizontalOffset(
            bounds: bounds,
            displayScale: 1,
            position: 0.25
        )

        #expect(abs(left + 94.91) < 0.02)
        #expect(abs(center + 3.67) < 0.02)
        #expect(abs(right - 87.57) < 0.02)
        #expect(abs(quarter - (left + (right - left) * 0.25)) < 0.001)
    }
}

struct PetLayoutMetricsTests {
    private let metrics = PetLayoutMetrics.live

    @Test
    func overlapRatioMovesCharacterContinuouslyIntoPanelArea() {
        #expect(metrics.petStackSpacing(for: 0) == 8)
        #expect(metrics.petStackSpacing(for: 0.2) == 0)
        #expect(metrics.petStackSpacing(for: 0.3) == -4)
        #expect(metrics.petStackSpacing(for: 1) == -32)
    }

    @Test
    func overlapRatioIsClampedBeforeCalculatingSpacing() {
        #expect(metrics.petStackSpacing(for: -1) == 8)
        #expect(metrics.petStackSpacing(for: 2) == -32)
    }

    @Test
    func previewScalingPreservesTheSameOverlapGeometry() {
        let previewMetrics = metrics.scaled(by: 0.95)

        #expect(abs(previewMetrics.petStackSpacing(for: 0.21) + 0.38) < 0.001)
        #expect(abs(previewMetrics.petStackSpacing(for: 1) + 30.4) < 0.001)
    }
}

struct PetStateCoordinatorTests {
    @Test @MainActor
    func conversationLifecycleAndStaleEvents() {
        let now = Date(timeIntervalSince1970: 100)
        let coordinator = PetStateCoordinator(now: now)
        let activeID = UUID()
        let staleID = UUID()

        coordinator.send(.conversationStarted(activeID), at: now)
        #expect(coordinator.snapshot.activityState == .thinking)
        coordinator.send(.conversationStreamStarted(activeID), at: now.addingTimeInterval(1))
        #expect(coordinator.snapshot.activityState == .talking)

        coordinator.send(.conversationCompleted(staleID), at: now.addingTimeInterval(2))
        #expect(coordinator.snapshot.activityState == .talking)
        #expect(coordinator.snapshot.runID == activeID)
    }

    @Test @MainActor
    func confirmationCannotBeOverriddenByBackgroundWork() {
        let coordinator = PetStateCoordinator()
        let commandID = UUID()
        coordinator.send(.conversationStarted(commandID))
        coordinator.send(.commandConfirmationRequested(commandID))

        coordinator.send(.automationStarted(UUID()))
        coordinator.send(.interaction(.clicked, nil))

        #expect(coordinator.snapshot.activityState == .waitingForConfirmation)
        #expect(coordinator.snapshot.renderedState == .waitingForConfirmation)
        #expect(coordinator.snapshot.hasPendingConfirmation)
    }

    @Test @MainActor
    func transientSuccessFallsBackToLatestSnapshot() {
        let now = Date(timeIntervalSince1970: 200)
        let coordinator = PetStateCoordinator(now: now)
        let runID = UUID()

        coordinator.send(.conversationStarted(runID), at: now)
        coordinator.send(.conversationCompleted(runID), at: now.addingTimeInterval(1))
        #expect(coordinator.snapshot.activityState == .idle)
        #expect(coordinator.snapshot.renderedState == .success)

        coordinator.expireTransientEffect(at: now.addingTimeInterval(4))
        #expect(coordinator.snapshot.activityState == .idle)
        #expect(coordinator.snapshot.renderedState == .idle)
        #expect(coordinator.transientEffect == nil)
    }

    @Test @MainActor
    func sleepOnlyStartsFromIdle() {
        let coordinator = PetStateCoordinator()
        let runID = UUID()
        coordinator.send(.conversationStarted(runID))
        coordinator.send(.idleTimeoutReached)
        #expect(coordinator.snapshot.activityState == .thinking)

        coordinator.send(.resetToIdle)
        coordinator.send(.idleTimeoutReached)
        #expect(coordinator.snapshot.activityState == .sleeping)
    }

    @Test @MainActor
    func foregroundWorkInterruptsClickEffect() {
        let coordinator = PetStateCoordinator()
        coordinator.send(.interaction(.clicked, 5))
        #expect(coordinator.transientEffect == .clicked)

        coordinator.send(.conversationStarted(UUID()))
        #expect(coordinator.snapshot.activityState == .thinking)
        #expect(coordinator.transientEffect == nil)
    }
}

struct PetAssetResolverTests {
    @Test
    func missingWorkingAssetFallsBackToIdle() {
        let idle = PetAnimationAsset(id: "idle", location: "idle.png", type: .png)
        let character = PetCharacter(
            id: "test",
            name: "Test",
            assetsByState: [.idle: [idle]],
            autoMessages: []
        )

        let resolved = PetAssetResolver().resolve(
            character: character,
            state: .working,
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(resolved?.asset.id == "idle")
        #expect(resolved?.resolvedState == .idle)
    }

    @Test
    func interactionAssetWinsForClickEffect() {
        let idle = PetAnimationAsset(id: "idle", location: "idle.gif")
        let click = PetAnimationAsset(id: "click", location: "click.gif", loop: false)
        let character = PetCharacter(
            id: "test",
            name: "Test",
            assetsByState: [.idle: [idle]],
            interactionAssets: [click],
            autoMessages: []
        )

        let resolved = PetAssetResolver().resolve(
            character: character,
            state: .idle,
            transientEffect: .clicked,
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(resolved?.asset.id == "click")
        #expect(resolved?.isInteractionAsset == true)
    }

    @Test
    func oldTwoGifCharacterIsRejectedByConfirmedMigrationPolicy() {
        let legacyJSON = #"{"name":"旧角色","normalGif":"idle.gif","clickGif":"tap.gif","autoMessages":[]}"#
        let decoded = try? JSONDecoder().decode(PetCharacter.self, from: Data(legacyJSON.utf8))
        #expect(decoded == nil)
    }

    @Test
    func newCharacterRoundTrips() throws {
        let character = PetCharacter(
            id: "stable-id",
            name: "新角色",
            assetsByState: [
                .idle: [PetAnimationAsset(id: "idle", location: "idle.png", type: .png)],
                .thinking: [PetAnimationAsset(id: "thinking", location: "thinking.gif")]
            ],
            autoMessages: ["你好"]
        )
        let data = try JSONEncoder().encode(character)
        let decoded = try JSONDecoder().decode(PetCharacter.self, from: data)
        #expect(decoded == character)
        #expect(decoded.id == "stable-id")
    }
}

struct PetWindowGeometryTests {
    @Test
    func growingContentPreservesPetAnchor() {
        let current = NSRect(x: 500, y: 160, width: 280, height: 280)
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

        let expanded = PetWindowGeometry.anchoredFrame(
            currentFrame: current,
            proposedContentSize: CGSize(width: 340, height: 390),
            visibleFrame: visible
        )

        #expect(expanded.midX == current.midX)
        #expect(expanded.minY == current.minY)
        #expect(expanded.width == 340)
        #expect(expanded.height == 390)
    }

    @Test
    func expansionAtScreenEdgeNeverMovesPetAnchor() {
        let current = NSRect(x: 1_250, y: 720, width: 280, height: 280)
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

        let expanded = PetWindowGeometry.anchoredFrame(
            currentFrame: current,
            proposedContentSize: CGSize(width: 360, height: 520),
            visibleFrame: visible
        )

        #expect(expanded.midX == current.midX)
        #expect(expanded.minY == current.minY)
        #expect(expanded.maxX > visible.maxX)
        #expect(expanded.maxY > visible.maxY)
    }

    @Test
    func contentCanShrinkWindowToOneHundredEightyPoints() {
        let current = NSRect(x: 500, y: 160, width: 336, height: 346)
        let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

        let shrunk = PetWindowGeometry.anchoredFrame(
            currentFrame: current,
            proposedContentSize: CGSize(width: 120, height: 140),
            visibleFrame: visible
        )

        #expect(shrunk.size == PetWindowSizing.minimumSize)
        #expect(shrunk.midX == current.midX)
        #expect(shrunk.minY == current.minY)
    }
}

struct WindowResizeGeometryTests {
    private let initial = NSRect(x: 100, y: 100, width: 560, height: 440)
    private let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)
    private let minimum = NSSize(width: 420, height: 320)

    @Test
    func draggingTopRightCornerExpandsBothDimensions() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: 80, y: 60),
            edges: [.right, .top],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.minX == initial.minX)
        #expect(resized.minY == initial.minY)
        #expect(resized.width == 640)
        #expect(resized.height == 500)
    }

    @Test
    func draggingLeftAndBottomPreservesOppositeCorner() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: -50, y: -25),
            edges: [.left, .bottom],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.maxX == initial.maxX)
        #expect(resized.maxY == initial.maxY)
        #expect(resized.width == 610)
        #expect(resized.height == 465)
    }

    @Test
    func shrinkingStopsAtMinimumSize() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: -500, y: -500),
            edges: [.right, .top],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.size == minimum)
        #expect(resized.origin == initial.origin)
    }

    @Test
    func expansionStopsAtVisibleScreenEdges() {
        let resized = WindowResizeGeometry.resizedFrame(
            initialFrame: initial,
            screenDelta: NSPoint(x: -500, y: 800),
            edges: [.left, .top],
            minimumSize: minimum,
            visibleFrame: visible
        )

        #expect(resized.minX == visible.minX)
        #expect(resized.maxY == visible.maxY)
    }
}

struct PetWindowScaleGeometryTests {
    private let initial = NSRect(x: 500, y: 120, width: 336, height: 346)
    private let visible = NSRect(x: 0, y: 40, width: 1_440, height: 860)

    @Test
    func horizontalDragScalesPetUniformlyFromBottomEdge() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 420, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible
        )

        #expect(resized.minX == initial.minX)
        #expect(resized.minY == initial.minY)
        #expect(resized.width == 420)
        #expect(resized.height == 432.5)
    }

    @Test
    func leftBottomCornerPreservesOppositeCorner() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 416, y: 40, width: 420, height: 426),
            edges: [.left, .bottom],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible
        )

        #expect(resized.maxX == initial.maxX)
        #expect(resized.maxY == initial.maxY)
        #expect(resized.width / initial.width == resized.height / initial.height)
    }

    @Test
    func shrinkingStopsBeforeEitherDimensionDropsBelowMinimum() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 100, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible
        )

        #expect(resized.width == 180)
        #expect(resized.height >= 180)
    }

    @Test
    func resizingHonorsConfiguredScaleLimit() {
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 1_000, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible,
            maximumScaleFactor: 1.5
        )

        #expect(resized.width == initial.width * 1.5)
        #expect(resized.height == initial.height * 1.5)
    }

    @Test
    func fixedPanelHeightDoesNotScaleWithCharacter() {
        let initial = NSRect(x: 500, y: 120, width: 356, height: 346)
        let fixedPanelHeight: CGFloat = 66
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 267, height: 346),
            edges: [.right],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible,
            fixedContentHeight: fixedPanelHeight
        )

        #expect(resized.width == 267)
        #expect(resized.height == 276)
        #expect(resized.height - PetWindowSizing.characterBaseHeight * 0.75 == fixedPanelHeight)
    }

    @Test
    func verticalDragDerivesScaleAfterSubtractingFixedPanelHeight() {
        let initial = NSRect(x: 500, y: 120, width: 356, height: 346)
        let resized = PetWindowScaleGeometry.uniformlyResizedFrame(
            initialFrame: initial,
            proposedFrame: NSRect(x: 500, y: 120, width: 356, height: 276),
            edges: [.top],
            minimumSize: PetWindowSizing.minimumSize,
            visibleFrame: visible,
            fixedContentHeight: 66
        )

        #expect(resized.width == 267)
        #expect(resized.height == 276)
        #expect(resized.minY == initial.minY)
    }
}

struct PetWindowRuntimeSizingTests {
    @Test
    func contentScaleIsClampedToSupportedPreferenceRange() {
        #expect(PetWindowSizing.clampedContentScale(0.1) == 0.5)
        #expect(PetWindowSizing.clampedContentScale(1.25) == 1.25)
        #expect(PetWindowSizing.clampedContentScale(3) == 2)
    }

    @Test
    func panelWidthTracksWindowScaleWithoutScalingPanelContent() {
        #expect(PetWindowSizing.panelWidth(for: 0.5) == 164)
        #expect(PetWindowSizing.panelWidth(for: 1) == 340)
        #expect(PetWindowSizing.panelWidth(for: 2) == 696)
    }

    @Test
    func layoutPreviewPreservesActualCharacterToPanelRatioAtEveryScale() {
        for contentScale: CGFloat in [0.5, 1, 2] {
            let preview = PetLayoutPreviewGeometry(contentScale: contentScale)
            let previewRatio = preview.characterHeight / preview.panelWidth
            let liveRatio = PetWindowSizing.characterBaseHeight * contentScale
                / PetWindowSizing.panelWidth(for: contentScale)

            #expect(abs(previewRatio - liveRatio) < 0.0001)
        }
    }

    @Test
    func layoutPreviewUsesSameNormalizationForInputAndCharacter() {
        let preview = PetLayoutPreviewGeometry(contentScale: 1)

        #expect(abs(preview.scaledPanelMetric(340) - preview.panelWidth) < 0.0001)
        #expect(
            abs(
                preview.characterHeight
                    / preview.scaledPanelMetric(PetPanelLayoutMetrics.inputHeight)
                    - PetWindowSizing.characterBaseHeight / PetPanelLayoutMetrics.inputHeight
            ) < 0.0001
        )
    }

    @Test @MainActor
    func scaledContentReportsItsVisualSizeInsteadOfUnscaledLayoutSize() {
        let rootView = PetWindowScaledContent(scale: 0.5) {
            Color.red
                .frame(width: 336, height: 346)
                .fixedSize()
        }
        let hostingView = NSHostingView(rootView: rootView)

        #expect(hostingView.fittingSize.width == 168)
        #expect(hostingView.fittingSize.height == 173)
    }

    @Test @MainActor
    func hostingFixedPetContentStillAcceptsOneHundredEightyPointWindow() {
        let rootView = Color.clear
            .frame(width: 336, height: 346)
            .fixedSize()
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 346),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.contentMinSize = PetWindowSizing.minimumSize

        window.setFrame(
            NSRect(x: 0, y: 0, width: 180, height: 186),
            display: false,
            animate: false
        )
        hostingView.layoutSubtreeIfNeeded()

        #expect(window.contentMinSize == PetWindowSizing.minimumSize)
        #expect(window.frame.width == 180)
    }
}

struct OptionWindowResizeModeTests {
    @Test @MainActor
    func dialogWindowForwardsOptionModifierToNativeOverlay() {
        let window = DialogWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        let overlay = OptionWindowResizeNSView(frame: window.contentView?.bounds ?? .zero)
        window.resizeOverlay = overlay

        window.updateResizeMode(for: [.option])
        #expect(overlay.isResizeModeActive)

        window.updateResizeMode(for: [])
        #expect(!overlay.isResizeModeActive)
    }

    @Test @MainActor
    func nativeOverlayTracksContainerSize() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 440))
        let overlay = OptionWindowResizeNSView(frame: container.bounds)
        overlay.autoresizingMask = [.width, .height]
        container.addSubview(overlay)

        container.setFrameSize(NSSize(width: 720, height: 520))
        container.layoutSubtreeIfNeeded()

        #expect(overlay.frame.size == container.bounds.size)
    }

    @Test @MainActor
    func resizeContainerOverlayWinsHitTestingAboveHostingView() {
        let hostingView = NSHostingView(
            rootView: Color.clear.frame(width: 336, height: 346).fixedSize()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 336, height: 346),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let container = WindowResizeContainerNSView(
            frame: NSRect(x: 0, y: 0, width: 336, height: 346)
        )
        window.contentView = container
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        let overlay = OptionWindowResizeNSView(frame: container.bounds)
        overlay.setResizeModeActive(true)
        container.addSubview(overlay, positioned: .above, relativeTo: hostingView)

        let rightEdgePoint = NSPoint(
            x: container.bounds.maxX - 4,
            y: container.bounds.midY
        )
        #expect(container.hitTest(rightEdgePoint) === overlay)
    }

    @Test @MainActor
    func activeOverlayRendersOrangeBorder() throws {
        let overlay = OptionWindowResizeNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 120))
        overlay.cornerRadius = 24
        overlay.setResizeModeActive(true)

        let bitmap = try #require(overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds))
        overlay.cacheDisplay(in: overlay.bounds, to: bitmap)

        var foundAccentPixel = false
        for x in 0..<bitmap.pixelsWide where !foundAccentPixel {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.45,
                   color.redComponent > 0.7,
                   color.greenComponent > 0.3,
                   color.redComponent > color.greenComponent,
                   color.greenComponent > color.blueComponent {
                    foundAccentPixel = true
                    break
                }
            }
        }

        #expect(foundAccentPixel)
    }
}
