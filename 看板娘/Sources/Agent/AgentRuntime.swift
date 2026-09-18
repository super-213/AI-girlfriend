//
//  AgentRuntime.swift
//  看板娘
//
//  Source-compatible UI facade backed by AgentRunner.
//

import Foundation

@MainActor
protocol AgentModelClient: AnyObject {
    var contextWindowConfigurationIdentifier: String { get }
    func resolveContextWindowTokenCount(
        completion: @escaping @MainActor @Sendable (Int?) -> Void
    )
    func sendAgentStreamRequest(
        messages: [AgentMessage],
        tools: [AgentToolDefinition],
        purpose: AgentRequestPurpose,
        onReceive: @escaping @MainActor @Sendable (String) -> Void,
        onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
        onError: @escaping @MainActor @Sendable (Error) -> Void
    )
    func cancelStreamRequest()
}

extension AgentModelClient {
    var contextWindowConfigurationIdentifier: String { "context-window-unavailable" }

    func resolveContextWindowTokenCount(
        completion: @escaping @MainActor @Sendable (Int?) -> Void
    ) {
        completion(nil)
    }
}

extension APIManager: AgentModelClient {}

struct AgentPendingApproval {
    let toolName: String
    let summary: String
}

/// Compatibility facade for existing AppKit/SwiftUI consumers.
/// All model/tool iteration and run state are owned by `AgentRunner`.
@MainActor
final class AgentRuntime {
    var onAssistantResponseStarted: (() -> Void)?
    var onAssistantText: ((String) -> Void)?
    var onToolStarted: ((String) -> Void)?
    var onToolFinished: ((String, AgentToolExecutionResult) -> Void)?
    var onApprovalRequested: ((AgentPendingApproval) -> Void)?
    var onContextCompactionStarted: (() -> Void)?
    var onContextCompacted: ((AgentContextCompactionEvent) -> Void)?
    var onCompleted: (() -> Void)?
    var onError: ((Error) -> Void)?
    var additionalSystemContext: String?

    private(set) var messages: [AgentMessage] = []
    private(set) var isRunning = false

    private let apiManager: any AgentModelClient
    private let registry: AgentToolRegistry
    private let systemPromptProvider: @MainActor @Sendable () -> String
    private let enabledSkillNameResolver: @MainActor @Sendable (String) -> String?
    private let fallbackContextCompactionPolicy: AgentContextCompactionPolicy
    private let runConfiguration: RunConfiguration
    private let runner: AgentRunner

    private var session: MemoryAgentSession
    private var activeRun: AgentRun<String>?
    private var eventTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var activeAgent: AgentDefinition<Void, String>?
    private var pendingRunState: RunState?
    private var pendingInterruption: AgentInterruption?
    private var runToken = UUID()

    private var contextWindowLookupIdentifier: String?
    private var didResolveContextWindow = false
    private var resolvedContextWindowTokenCount: Int?
    private var lastCompactionAttemptMessageCount: Int?

    private var contextManager: AgentContextManager {
        AgentContextManager(
            policy: fallbackContextCompactionPolicy.adaptingTrigger(
                to: resolvedContextWindowTokenCount
            )
        )
    }

    init(
        apiManager: any AgentModelClient = APIManager(),
        registry: AgentToolRegistry = .standard(),
        contextCompactionPolicy: AgentContextCompactionPolicy = .standard,
        runConfiguration: RunConfiguration = RunConfiguration(),
        enabledSkillNameResolver: @escaping @MainActor @Sendable (String) -> String? = {
            if let skill = SkillLibrary.enabledSkill(named: $0) {
                return skill.name
            }
            if $0.caseInsensitiveCompare(KnowledgeBaseAnswerSkill.name) == .orderedSame,
               KnowledgeBaseRegistry.shared.hasEnabledKnowledgeBase {
                return KnowledgeBaseAnswerSkill.name
            }
            return nil
        },
        systemPromptProvider: @escaping @MainActor @Sendable () -> String
    ) {
        self.apiManager = apiManager
        self.registry = registry
        fallbackContextCompactionPolicy = contextCompactionPolicy
        self.runConfiguration = runConfiguration
        self.enabledSkillNameResolver = enabledSkillNameResolver
        self.systemPromptProvider = systemPromptProvider
        session = MemoryAgentSession()

        let provider = LegacyModelProvider(
            client: apiManager,
            normalizeToolCall: { call in
                guard registry.tool(named: call.name) == nil,
                      registry.tool(named: "read_skill") != nil,
                      let canonicalName = enabledSkillNameResolver(call.name),
                      let data = try? JSONSerialization.data(
                          withJSONObject: ["name": canonicalName],
                          options: [.sortedKeys]
                      ),
                      let arguments = String(data: data, encoding: .utf8) else {
                    return call
                }
                return AgentToolCall(id: call.id, name: "read_skill", arguments: arguments)
            }
        )
        runner = AgentRunner(provider: provider)
    }

    func send(
        _ rawText: String,
        imagePaths: [String] = [],
        explicitInvocation: AgentInvocation? = nil
    ) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isRunning else {
            onError?(AgentError.busy)
            return
        }
        do {
            try runConfiguration.validate()
        } catch {
            onError?(error)
            return
        }

        isRunning = true
        let token = UUID()
        runToken = token
        let modelText = decoratedInput(text, explicitInvocation: explicitInvocation)
        Task { @MainActor [weak self] in
            await self?.prepareAndStart(
                text: modelText,
                imagePaths: imagePaths,
                explicitInvocation: explicitInvocation,
                token: token
            )
        }
    }

    func startNewConversation() {
        cancel()
        messages.removeAll()
        session = MemoryAgentSession()
        resetCompactionState()
    }

    func restoreConversation(_ history: [AgentMessage]) {
        cancel()
        messages = history
        session = MemoryAgentSession(items: AgentItemLegacyCodec.items(from: history))
        resetCompactionState()
    }

    func cancel() {
        runToken = UUID()
        activeRun?.cancel()
        eventTask?.cancel()
        resultTask?.cancel()
        apiManager.cancelStreamRequest()
        activeRun = nil
        eventTask = nil
        resultTask = nil
        activeAgent = nil
        pendingRunState = nil
        pendingInterruption = nil
        isRunning = false
    }

    func approvePendingTool() {
        resumePendingTool(with: .approved)
    }

    func declinePendingTool() {
        resumePendingTool(with: .rejected(reason: "用户拒绝执行该工具"))
    }

    private func prepareAndStart(
        text: String,
        imagePaths: [String],
        explicitInvocation: AgentInvocation?,
        token: UUID
    ) async {
        guard runToken == token, isRunning else { return }
        refreshSystemPrompt()

        var followingItems: [AgentItem] = []
        var forceCompaction = false
        if let explicitInvocation, explicitInvocation.kind == .skill {
            do {
                followingItems = try await forcedSkillItems(named: explicitInvocation.name)
            } catch {
                finishWithError(error, token: token)
                return
            }
        } else if let explicitInvocation,
                  explicitInvocation.kind == .tool,
                  explicitInvocation.name == AgentRuntimeToolName.compactContext {
            followingItems = forcedCompactionItems()
            forceCompaction = true
        }

        await resolveContextWindowIfNeeded(token: token)
        guard runToken == token, isRunning else { return }
        let preparedHistory = await compactHistoryIfNeeded(
            input: text,
            imagePaths: imagePaths,
            followingItems: followingItems,
            force: forceCompaction,
            token: token
        )
        guard runToken == token, isRunning else { return }

        messages = preparedHistory
        session = MemoryAgentSession(
            id: session.id,
            items: AgentItemLegacyCodec.items(from: preparedHistory)
        )
        let agent = makeAgent()
        activeAgent = agent
        bind(
            runner.run(
                agent: agent,
                input: AgentInput(
                    text,
                    imagePaths: imagePaths,
                    followingItems: followingItems
                ),
                context: (),
                session: session,
                configuration: runConfiguration
            ),
            agent: agent,
            token: token
        )
    }

    private func bind(
        _ run: AgentRun<String>,
        agent: AgentDefinition<Void, String>,
        token: UUID
    ) {
        activeRun = run
        let events = Task { @MainActor [weak self] in
            do {
                for try await event in run.events {
                    guard let self, self.runToken == token else { return }
                    self.consume(event)
                }
            } catch {
                // Result task owns terminal error delivery to avoid duplicate UI callbacks.
            }
        }
        eventTask = events
        resultTask = Task { @MainActor [weak self] in
            do {
                let result = try await run.result.value
                _ = await events.result
                guard let self, self.runToken == token else { return }
                self.messages = AgentItemLegacyCodec.messages(from: result.history)
                self.pendingRunState = result.resumableState
                self.pendingInterruption = result.interruptions.first
                if result.resumableState == nil {
                    self.isRunning = false
                    self.activeRun = nil
                    self.activeAgent = nil
                    self.onCompleted?()
                }
            } catch {
                _ = await events.result
                guard let self, self.runToken == token else { return }
                self.finishWithError(error, token: token)
            }
        }
    }

    private func consume(_ event: AgentRunEvent) {
        switch event {
        case .modelStarted:
            onAssistantResponseStarted?()
        case .textDelta(let text):
            onAssistantText?(text)
        case .toolCallStarted(let call):
            AgentToolAuditStore.shared.record(
                toolName: call.name,
                summary: "执行工具 \(call.name)",
                status: .running
            )
            onToolStarted?(call.name)
        case .toolCallCompleted(let item):
            let result = legacyResult(from: item)
            AgentToolAuditStore.shared.record(
                toolName: item.toolName,
                summary: "执行工具 \(item.toolName)",
                status: result.isError ? .failed : .succeeded,
                detail: result.content
            )
            onToolFinished?(item.toolName, result)
        case .approvalRequired(let interruption):
            AgentToolAuditStore.shared.record(
                toolName: interruption.toolCall.name,
                summary: interruption.summary,
                status: .requested
            )
            onApprovalRequested?(AgentPendingApproval(
                toolName: interruption.toolCall.name,
                summary: interruption.summary
            ))
        case .contextCompactionStarted:
            onContextCompactionStarted?()
        case .contextCompacted(let event):
            onContextCompacted?(AgentContextCompactionEvent(
                summarizedMessageCount: event.summarizedItemCount,
                retainedMessageCount: event.retainedItemCount,
                estimatedTokensBeforeCompaction: event.estimatedTokensBeforeCompaction
            ))
        case .runStarted, .agentStarted, .modelCompleted, .usageUpdated,
             .handoff, .runCompleted, .runFailed:
            break
        }
    }

    private func resumePendingTool(with decision: ApprovalDecision) {
        guard isRunning,
              let state = pendingRunState,
              let interruption = pendingInterruption,
              let agent = activeAgent else { return }

        pendingRunState = nil
        pendingInterruption = nil
        AgentToolAuditStore.shared.record(
            toolName: interruption.toolCall.name,
            summary: interruption.summary,
            status: decision == .approved ? .approved : .declined
        )
        let token = runToken
        bind(
            runner.resume(
                agent: agent,
                from: state,
                decisions: [interruption.id: decision],
                context: (),
                session: session,
                configuration: runConfiguration
            ),
            agent: agent,
            token: token
        )
    }

    private func makeAgent() -> AgentDefinition<Void, String> {
        AgentDefinition(
            id: "desktop-companion",
            name: "Desktop Companion Agent",
            instructions: .fixed(makeSystemPrompt()),
            tools: LegacyAgentRuntimeAdapter.makeTools(registry: registry)
        )
    }

    private func forcedSkillItems(named requestedName: String) async throws -> [AgentItem] {
        guard let canonicalName = enabledSkillNameResolver(requestedName),
              let tool = registry.tool(named: "read_skill"),
              let data = try? JSONSerialization.data(
                  withJSONObject: ["name": canonicalName],
                  options: [.sortedKeys]
              ),
              let arguments = String(data: data, encoding: .utf8) else {
            throw AgentRuntimeError.skillUnavailable(requestedName)
        }
        let call = AgentToolCall(
            id: "forced-skill-\(UUID().uuidString)",
            name: "read_skill",
            arguments: arguments
        )
        onToolStarted?(call.name)
        let result = await executeLegacyTool(tool, arguments: ["name": canonicalName])
        onToolFinished?(call.name, result)
        guard !result.isError else {
            throw AgentError.toolExecutionFailed(toolName: call.name, detail: result.content)
        }
        return [
            .message(AgentMessageItem(role: .assistant, content: nil)),
            .toolCall(ToolCallItem(id: call.id, name: call.name, arguments: call.arguments)),
            .toolResult(ToolResultItem(
                toolCallID: call.id,
                toolName: call.name,
                content: result.modelContent,
                isError: false,
                imagePaths: result.imagePaths
            ))
        ]
    }

    private func forcedCompactionItems() -> [AgentItem] {
        let call = AgentToolCall(
            id: "forced-tool-\(UUID().uuidString)",
            name: AgentRuntimeToolName.compactContext,
            arguments: "{}"
        )
        let result = AgentToolExecutionResult.success(
            "已请求压缩当前会话上下文；Runtime 将保留最新完整轮次，并摘要更早内容。"
        )
        onToolStarted?(call.name)
        onToolFinished?(call.name, result)
        return [
            .message(AgentMessageItem(role: .assistant, content: nil)),
            .toolCall(ToolCallItem(id: call.id, name: call.name, arguments: call.arguments)),
            .toolResult(ToolResultItem(
                toolCallID: call.id,
                toolName: call.name,
                content: result.modelContent,
                isError: false
            ))
        ]
    }

    private func executeLegacyTool(
        _ tool: any LegacyAgentTool,
        arguments: [String: Any]
    ) async -> AgentToolExecutionResult {
        await withCheckedContinuation { continuation in
            tool.execute(arguments: arguments) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func resolveContextWindowIfNeeded(token: UUID) async {
        let identifier = apiManager.contextWindowConfigurationIdentifier
        if contextWindowLookupIdentifier != identifier {
            contextWindowLookupIdentifier = identifier
            didResolveContextWindow = false
            resolvedContextWindowTokenCount = nil
            lastCompactionAttemptMessageCount = nil
        }
        guard !didResolveContextWindow else { return }
        let count = await withCheckedContinuation { continuation in
            apiManager.resolveContextWindowTokenCount { continuation.resume(returning: $0) }
        }
        guard runToken == token,
              apiManager.contextWindowConfigurationIdentifier == identifier else { return }
        didResolveContextWindow = true
        resolvedContextWindowTokenCount = count
    }

    private func compactHistoryIfNeeded(
        input: String,
        imagePaths: [String],
        followingItems: [AgentItem],
        force: Bool,
        token: UUID
    ) async -> [AgentMessage] {
        let inputMessage = AgentMessage.user(input, imagePaths: imagePaths)
        let followingMessages = AgentItemLegacyCodec.messages(from: followingItems)
        let currentSequence = [inputMessage] + followingMessages
        let candidate = messages + currentSequence
        guard force || lastCompactionAttemptMessageCount != candidate.count,
              let plan = contextManager.makePlan(
                  messages: candidate,
                  tools: registry.definitions,
                  previousMeasurement: nil,
                  force: force
              ),
              let systemMessage = candidate.first(where: {
                  $0.role == .system && $0.contextKind == nil
              }) else {
            return messages
        }

        lastCompactionAttemptMessageCount = candidate.count
        consume(.contextCompactionStarted)
        let response = await requestCompaction(plan: plan, token: token)
        guard runToken == token,
              let response,
              !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return messages
        }
        var compacted = contextManager.compactedMessages(
            systemMessage: systemMessage,
            summary: response.content,
            plan: plan
        )
        if compacted.count >= currentSequence.count,
           Array(compacted.suffix(currentSequence.count)) == currentSequence {
            compacted.removeLast(currentSequence.count)
        }
        lastCompactionAttemptMessageCount = nil
        consume(.contextCompacted(CompactionEvent(
            summarizedItemCount: plan.messagesToSummarize.count,
            retainedItemCount: plan.recentMessages.count,
            estimatedTokensBeforeCompaction: plan.estimatedTokensBeforeCompaction
        )))
        return compacted
    }

    private func requestCompaction(
        plan: AgentContextCompactionPlan,
        token: UUID
    ) async -> AgentModelResponse? {
        await withCheckedContinuation { continuation in
            var resumed = false
            func finish(_ response: AgentModelResponse?) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: response)
            }
            apiManager.sendAgentStreamRequest(
                messages: contextManager.summaryRequestMessages(for: plan),
                tools: [],
                purpose: .contextCompaction,
                onReceive: { _ in },
                onComplete: { response in finish(response) },
                onError: { _ in finish(nil) }
            )
        }
    }

    private func decoratedInput(
        _ text: String,
        explicitInvocation: AgentInvocation?
    ) -> String {
        guard let explicitInvocation, explicitInvocation.kind == .tool else { return text }
        return """
        \(text)

        <explicit-tool-context name="\(explicitInvocation.name)">
        用户通过输入框将此工具显式附加到本轮上下文。请将它视为与当前任务可能相关的工具，但不要因此排除其他工具，也不要在不需要时强行调用它。根据任务实际需要选择一个或多个可用工具。
        </explicit-tool-context>
        """
    }

    private func refreshSystemPrompt() {
        let prompt = makeSystemPrompt()
        if messages.first?.role == .system {
            messages[0].content = prompt
        } else if !messages.isEmpty {
            messages.insert(.system(prompt), at: 0)
        }
    }

    private func makeSystemPrompt() -> String {
        let environment = """

        ## 当前运行环境
        当前时区：\(TimeZone.current.identifier)
        如需当前日期、时间或星期，调用 get_current_datetime 工具获取，不要猜测。

        ## 工具调用规则
        你拥有客户端提供的结构化工具。需要实时信息或外部操作时必须调用合适的工具，不要声称自己没有权限。
        打开应用使用 open_application；搜索本机文件使用 search_files，不要优先使用 Shell。
        读取文本以外的常见文档、图片 OCR 或用户拖入的文件时使用 read_document。
        文件搜索结果不唯一时，先向用户列出候选项并请其选择，不要自行打开或修改某个结果。
        新建、覆盖、复制或移动文件使用受控文件工具，并在用户确认后执行。
        “可用 Skills”中的 name 只是工作流标识，不是工具名称；禁止直接调用 Skill name。
        用户任务匹配 Skill 时，只能先调用 read_skill，并将 Skill name 放入 name 参数。
        用户明确要求压缩、整理或缩短当前会话上下文时，调用 compact_context；不要仅用文本声称已经压缩。
        工具结果会作为 tool message 返回；根据结果继续处理，直到给出最终答复。
        不要在普通文本中伪造工具调用，不要输出“命令:”或“[命令]”协议。
        """
        return systemPromptProvider() + environment + (additionalSystemContext ?? "")
    }

    private func legacyResult(from item: ToolResultItem) -> AgentToolExecutionResult {
        guard let data = item.content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool,
              let result = object["result"] as? String else {
            return AgentToolExecutionResult(
                content: item.content,
                isError: item.isError,
                imagePaths: item.imagePaths
            )
        }
        return AgentToolExecutionResult(
            content: result,
            isError: item.isError || !ok,
            imagePaths: item.imagePaths
        )
    }

    private func finishWithError(_ error: Error, token: UUID) {
        guard runToken == token else { return }
        isRunning = false
        activeRun = nil
        activeAgent = nil
        pendingRunState = nil
        pendingInterruption = nil
        onError?(error)
    }

    private func resetCompactionState() {
        contextWindowLookupIdentifier = nil
        didResolveContextWindow = false
        resolvedContextWindowTokenCount = nil
        lastCompactionAttemptMessageCount = nil
    }
}
