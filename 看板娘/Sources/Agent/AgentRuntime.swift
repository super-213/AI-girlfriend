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

enum AgentRuntimeEvent: Sendable {
    case run(AgentRunEvent)
    case sessionUpdated(AgentSessionSnapshot)
}

extension ToolResultItem {
    var displayExecutionResult: AgentToolExecutionResult {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? Bool,
              let result = object["result"] as? String else {
            return AgentToolExecutionResult(
                content: content,
                isError: isError,
                imagePaths: imagePaths
            )
        }
        return AgentToolExecutionResult(
            content: result,
            isError: isError || !ok,
            imagePaths: imagePaths
        )
    }
}

typealias AgentSessionFactory = @MainActor @Sendable (AgentSessionSnapshot) -> any AgentSession

/// Application facade backed by AgentRunner and one authoritative AgentSession.
@MainActor
final class AgentRuntime {
    let events: AsyncStream<AgentRuntimeEvent>
    var additionalSystemContext: String?
    var projectID: UUID?
    var workspacePath: String?
    var characterID: String?

    private(set) var isRunning = false
    private(set) var sessionSnapshot: AgentSessionSnapshot

    private let apiManager: any AgentModelClient
    private let registry: AgentToolRegistry
    private let systemPromptProvider: @MainActor @Sendable () -> String
    private let enabledSkillNameResolver: @MainActor @Sendable (String) -> String?
    private let fallbackContextCompactionPolicy: AgentContextCompactionPolicy
    private let runConfiguration: RunConfiguration
    private let runner: AgentRunner
    private let sessionFactory: AgentSessionFactory
    private let eventContinuation: AsyncStream<AgentRuntimeEvent>.Continuation

    private var session: any AgentSession
    private var activeRun: AgentRun<String>?
    private var eventTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?
    private var activeAgent: AgentDefinition<AppAgentContext, String>?
    private var pendingRunState: RunState?
    private var pendingInterruption: AgentInterruption?
    private var runToken = UUID()

    private var contextWindowLookupIdentifier: String?
    private var didResolveContextWindow = false
    private var resolvedContextWindowTokenCount: Int?

    init(
        apiManager: any AgentModelClient = APIManager(),
        registry: AgentToolRegistry = .standard(),
        contextCompactionPolicy: AgentContextCompactionPolicy = .standard,
        runConfiguration: RunConfiguration = RunConfiguration(),
        modelProvider: (any AgentModelProvider)? = nil,
        tracer: any AgentTracer = AppAgentTracer.shared,
        sessionFactory: @escaping AgentSessionFactory = { snapshot in
            MemoryAgentSession(
                id: snapshot.sessionID,
                items: snapshot.items,
                runState: snapshot.pendingRunState
            )
        },
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
        self.sessionFactory = sessionFactory
        self.enabledSkillNameResolver = enabledSkillNameResolver
        self.systemPromptProvider = systemPromptProvider
        var continuation: AsyncStream<AgentRuntimeEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(512)) {
            continuation = $0
        }
        eventContinuation = continuation
        let initialSnapshot = AgentSessionSnapshot(
            providerConfigurationID: apiManager.contextWindowConfigurationIdentifier
        )
        sessionSnapshot = initialSnapshot
        session = sessionFactory(initialSnapshot)

        let baseProvider: any AgentModelProvider
        if let modelProvider {
            baseProvider = modelProvider
        } else if let manager = apiManager as? APIManager {
            baseProvider = manager.makeAgentModelProvider()
        } else {
            baseProvider = LegacyModelProvider(client: apiManager)
        }
        let provider = ToolCallNormalizingModelProvider(base: baseProvider) { call in
            guard !registry.containsTool(named: call.name),
                  registry.containsTool(named: "read_skill"),
                  let canonicalName = enabledSkillNameResolver(call.name),
                  let data = try? JSONSerialization.data(
                    withJSONObject: ["name": canonicalName],
                    options: [.sortedKeys]
                  ),
                  let arguments = String(data: data, encoding: .utf8) else {
                return call
            }
            return ToolCallItem(id: call.id, name: "read_skill", arguments: arguments)
        }
        runner = AgentRunner(provider: provider, tracer: tracer)
    }

    func send(
        _ rawText: String,
        imagePaths: [String] = [],
        explicitInvocation: AgentInvocation? = nil
    ) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isRunning else {
            eventContinuation.yield(.run(.runFailed(.busy)))
            return
        }
        do {
            try runConfiguration.validate()
        } catch {
            eventContinuation.yield(.run(.runFailed(Self.agentError(from: error))))
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
        let snapshot = AgentSessionSnapshot(
            providerConfigurationID: apiManager.contextWindowConfigurationIdentifier
        )
        sessionSnapshot = snapshot
        session = sessionFactory(snapshot)
        resetCompactionState()
        eventContinuation.yield(.sessionUpdated(snapshot))
    }

    func restoreConversation(_ history: [AgentMessage]) {
        restoreSession(AgentSessionSnapshot(
            legacyMessages: history,
            providerConfigurationID: apiManager.contextWindowConfigurationIdentifier
        ))
    }

    func restoreSession(_ snapshot: AgentSessionSnapshot) {
        cancel()
        sessionSnapshot = snapshot
        session = sessionFactory(snapshot)
        resetCompactionState()
        eventContinuation.yield(.sessionUpdated(snapshot))
        guard let state = snapshot.pendingRunState else { return }
        guard snapshot.schemaVersion == AgentSessionSnapshot.currentSchemaVersion,
              state.schemaVersion == RunState.currentSchemaVersion,
              state.sessionID == snapshot.sessionID else {
            eventContinuation.yield(.run(.runFailed(.approvalStateInvalid)))
            return
        }
        let agent = makeAgent()
        activeAgent = agent
        pendingRunState = state
        pendingInterruption = state.interruptions.first
        isRunning = true
        if let interruption = state.interruptions.first {
            eventContinuation.yield(.run(.approvalRequired(interruption)))
        }
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

        var preflightToolCalls: [ToolCallItem] = []
        if let explicitInvocation, explicitInvocation.kind == .skill {
            do {
                preflightToolCalls = [try forcedSkillCall(named: explicitInvocation.name)]
            } catch {
                await finishWithError(error, token: token)
                return
            }
        } else if let explicitInvocation,
                  explicitInvocation.kind == .tool,
                  explicitInvocation.name == AgentRuntimeToolName.compactContext {
            preflightToolCalls = [forcedCompactionCall()]
        }

        await resolveContextWindowIfNeeded(token: token)
        guard runToken == token, isRunning else { return }
        let agent = makeAgent()
        activeAgent = agent
        bind(
            runner.run(
                agent: agent,
                input: AgentInput(
                    text,
                    imagePaths: imagePaths,
                    preflightToolCalls: preflightToolCalls
                ),
                context: makeRunContext(),
                session: session,
                configuration: effectiveRunConfiguration(forceCompaction: false)
            ),
            agent: agent,
            token: token
        )
    }

    private func bind(
        _ run: AgentRun<String>,
        agent: AgentDefinition<AppAgentContext, String>,
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
                await self.updateSessionSnapshot()
                self.pendingRunState = result.resumableState
                self.pendingInterruption = result.interruptions.first
                if result.resumableState == nil {
                    self.isRunning = false
                    self.activeRun = nil
                    self.activeAgent = nil
                    self.eventContinuation.yield(.run(.runCompleted))
                } else if let interruption = result.interruptions.first {
                    self.eventContinuation.yield(.run(.approvalRequired(interruption)))
                }
            } catch {
                _ = await events.result
                guard let self, self.runToken == token else { return }
                await self.finishWithError(error, token: token)
            }
        }
    }

    private func consume(_ event: AgentRunEvent) {
        switch event {
        case .approvalRequired, .runCompleted, .runFailed:
            // Terminal and approval events are emitted only after the Session snapshot is current.
            break
        default:
            eventContinuation.yield(.run(event))
        }
    }

    private func resumePendingTool(with decision: ApprovalDecision) {
        guard isRunning,
              let state = pendingRunState,
              let interruption = pendingInterruption,
              let agent = activeAgent else { return }

        pendingRunState = nil
        pendingInterruption = nil
        let token = runToken
        bind(
            runner.resume(
                agent: agent,
                from: state,
                decisions: [interruption.id: decision],
                context: makeRunContext(),
                session: session,
                configuration: effectiveRunConfiguration(forceCompaction: false)
            ),
            agent: agent,
            token: token
        )
    }

    private func makeAgent() -> AgentDefinition<AppAgentContext, String> {
        AgentDefinition(
            id: "desktop-companion",
            name: "Desktop Companion Agent",
            instructions: .fixed(makeSystemPrompt()),
            tools: registry.allTypedTools,
            inputGuardrails: [AnyInputGuardrail(NonEmptyInputGuardrail<AppAgentContext>())],
            outputGuardrails: [AnyOutputGuardrail(AppAgentOutputGuardrail())],
            toolGuardrails: [AnyToolGuardrail(AppAgentToolGuardrail())]
        )
    }

    private func makeRunContext() -> AppAgentContext {
        let conversationID = UUID(uuidString: sessionSnapshot.sessionID) ?? UUID()
        let roots = workspacePath.map { [$0] } ?? []
        return AppAgentContext(
            conversationID: conversationID,
            projectID: projectID,
            workspacePath: workspacePath,
            characterID: characterID,
            fileAccessPolicy: AgentFileAccessStore.shared.makePolicy(additionalRoots: roots),
            commandPermissionPolicy: CommandPermissionPolicy()
        )
    }

    private func effectiveRunConfiguration(forceCompaction: Bool) -> RunConfiguration {
        var configuration = runConfiguration
        configuration.contextCompactionPolicy = fallbackContextCompactionPolicy.adaptingTrigger(
            to: resolvedContextWindowTokenCount
        )
        configuration.forceContextCompaction = forceCompaction
        return configuration
    }

    private func forcedSkillCall(named requestedName: String) throws -> ToolCallItem {
        guard let canonicalName = enabledSkillNameResolver(requestedName),
              registry.containsTool(named: "read_skill"),
              let data = try? JSONSerialization.data(
                  withJSONObject: ["name": canonicalName],
                  options: [.sortedKeys]
              ),
              let arguments = String(data: data, encoding: .utf8) else {
            throw AgentRuntimeError.skillUnavailable(requestedName)
        }
        return ToolCallItem(
            id: "forced-skill-\(UUID().uuidString)",
            name: "read_skill",
            arguments: arguments
        )
    }

    private func forcedCompactionCall() -> ToolCallItem {
        ToolCallItem(
            id: "forced-tool-\(UUID().uuidString)",
            name: AgentRuntimeToolName.compactContext,
            arguments: "{}"
        )
    }

    private func resolveContextWindowIfNeeded(token: UUID) async {
        let identifier = apiManager.contextWindowConfigurationIdentifier
        if contextWindowLookupIdentifier != identifier {
            contextWindowLookupIdentifier = identifier
            didResolveContextWindow = false
            resolvedContextWindowTokenCount = nil
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

    private func finishWithError(_ error: Error, token: UUID) async {
        guard runToken == token else { return }
        await updateSessionSnapshot()
        isRunning = false
        activeRun = nil
        activeAgent = nil
        pendingRunState = nil
        pendingInterruption = nil
        eventContinuation.yield(.run(.runFailed(Self.agentError(from: error))))
    }

    private func resetCompactionState() {
        contextWindowLookupIdentifier = nil
        didResolveContextWindow = false
        resolvedContextWindowTokenCount = nil
    }

    private func updateSessionSnapshot() async {
        do {
            sessionSnapshot = try await session.snapshot(
                createdAt: sessionSnapshot.createdAt,
                agentID: "desktop-companion",
                providerConfigurationID: apiManager.contextWindowConfigurationIdentifier
            )
            eventContinuation.yield(.sessionUpdated(sessionSnapshot))
        } catch {
            // Runner already retains the in-memory result. Keep the last export if
            // a custom session cannot be read back, and surface persistence errors
            // through the normal terminal path on its next operation.
        }
    }

    private static func agentError(from error: Error) -> AgentError {
        if let error = error as? AgentError { return error }
        return .modelRequestFailed(.transport(error.localizedDescription))
    }
}
