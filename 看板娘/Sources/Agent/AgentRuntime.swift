//
//  AgentRuntime.swift
//  看板娘
//
//  Iterative model -> tool -> observation runtime with human approval support.
//

import Foundation

@MainActor
protocol AgentModelClient: AnyObject {
    func sendAgentStreamRequest(
        messages: [AgentMessage],
        tools: [AgentToolDefinition],
        onReceive: @escaping @MainActor @Sendable (String) -> Void,
        onComplete: @escaping @MainActor @Sendable (AgentModelResponse) -> Void,
        onError: @escaping @MainActor @Sendable (Error) -> Void
    )
    func cancelStreamRequest()
}

extension APIManager: AgentModelClient {}

struct AgentPendingApproval {
    let toolName: String
    let summary: String
}

@MainActor
final class AgentRuntime {
    var onAssistantResponseStarted: (() -> Void)?
    var onAssistantText: ((String) -> Void)?
    var onToolStarted: ((String) -> Void)?
    var onToolFinished: ((String, AgentToolExecutionResult) -> Void)?
    var onApprovalRequested: ((AgentPendingApproval) -> Void)?
    var onCompleted: (() -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var messages: [AgentMessage] = []
    private(set) var isRunning = false

    private let apiManager: any AgentModelClient
    private let registry: AgentToolRegistry
    private let systemPromptProvider: () -> String
    private let enabledSkillNameResolver: (String) -> String?
    private let maxIterations: Int
    private var iterationCount = 0
    private var pendingCalls: [AgentToolCall] = []
    private var pendingApproval: (call: AgentToolCall, tool: any AgentTool, arguments: [String: Any])?
    private var runToken = UUID()

    init(
        apiManager: any AgentModelClient = APIManager(),
        registry: AgentToolRegistry = .standard(),
        maxIterations: Int = 8,
        enabledSkillNameResolver: @escaping (String) -> String? = {
            SkillLibrary.enabledSkill(named: $0)?.name
        },
        systemPromptProvider: @escaping () -> String
    ) {
        self.apiManager = apiManager
        self.registry = registry
        self.maxIterations = maxIterations
        self.enabledSkillNameResolver = enabledSkillNameResolver
        self.systemPromptProvider = systemPromptProvider
    }

    func send(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isRunning else {
            onError?(AgentRuntimeError.busy)
            return
        }

        if messages.isEmpty {
            messages.append(.system(makeSystemPrompt()))
        }
        messages.append(.user(text))
        iterationCount = 0
        isRunning = true
        requestModel()
    }

    func startNewConversation() {
        cancel()
        messages.removeAll()
    }

    /// Restores a previously selected conversation so the next request keeps
    /// its original model and tool context.
    func restoreConversation(_ history: [AgentMessage]) {
        cancel()
        messages = history
    }

    func cancel() {
        runToken = UUID()
        apiManager.cancelStreamRequest()
        pendingCalls.removeAll()
        pendingApproval = nil
        isRunning = false
    }

    func approvePendingTool() {
        guard let pendingApproval else { return }
        self.pendingApproval = nil
        execute(pendingApproval.call, with: pendingApproval.tool, arguments: pendingApproval.arguments)
    }

    func declinePendingTool() {
        guard let pendingApproval else { return }
        self.pendingApproval = nil
        let result = AgentToolExecutionResult.failure("用户拒绝执行该工具")
        messages.append(.tool(call: pendingApproval.call, content: result.modelContent))
        onToolFinished?(pendingApproval.call.name, result)
        executeNextToolCall()
    }

    private func requestModel() {
        guard isRunning else { return }
        guard iterationCount < maxIterations else {
            finishWithError(AgentRuntimeError.iterationLimit)
            return
        }
        iterationCount += 1
        refreshSystemPrompt()

        let token = runToken
        onAssistantResponseStarted?()
        apiManager.sendAgentStreamRequest(
            messages: messages,
            tools: registry.definitions,
            onReceive: { [weak self] text in
                guard let self, self.runToken == token else { return }
                self.onAssistantText?(text)
            },
            onComplete: { [weak self] response in
                guard let self, self.runToken == token else { return }
                self.handle(response)
            },
            onError: { [weak self] error in
                guard let self, self.runToken == token else { return }
                self.finishWithError(error)
            }
        )
    }

    private func handle(_ response: AgentModelResponse) {
        let toolCalls = response.toolCalls.map(normalizeSkillToolCall)
        messages.append(.assistant(
            content: response.content.isEmpty ? nil : response.content,
            toolCalls: toolCalls
        ))

        guard !toolCalls.isEmpty else {
            isRunning = false
            onCompleted?()
            return
        }

        pendingCalls = toolCalls
        executeNextToolCall()
    }

    /// Some models confuse a Skill catalog entry with a native function and
    /// emit `weather(...)` instead of `read_skill({"name":"weather"})`.
    /// Rewrite only exact enabled Skill names so the assistant/tool message
    /// pair remains protocol-valid and the model can continue the workflow.
    private func normalizeSkillToolCall(_ call: AgentToolCall) -> AgentToolCall {
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

    private func executeNextToolCall() {
        guard isRunning else { return }
        guard !pendingCalls.isEmpty else {
            requestModel()
            return
        }

        let call = pendingCalls.removeFirst()
        guard let tool = registry.tool(named: call.name) else {
            let error = AgentRuntimeError.toolUnavailable(call.name)
            let result = AgentToolExecutionResult.failure(error.localizedDescription)
            messages.append(.tool(call: call, content: result.modelContent))
            onToolFinished?(call.name, result)
            executeNextToolCall()
            return
        }

        let arguments: [String: Any]
        do {
            arguments = try call.decodedArguments()
        } catch {
            let result = AgentToolExecutionResult.failure(error.localizedDescription)
            messages.append(.tool(call: call, content: result.modelContent))
            onToolFinished?(call.name, result)
            executeNextToolCall()
            return
        }

        if tool.requiresConfirmation(arguments: arguments) {
            pendingApproval = (call, tool, arguments)
            onApprovalRequested?(
                AgentPendingApproval(
                    toolName: call.name,
                    summary: tool.approvalSummary(arguments: arguments)
                )
            )
            return
        }
        execute(call, with: tool, arguments: arguments)
    }

    private func execute(
        _ call: AgentToolCall,
        with tool: any AgentTool,
        arguments: [String: Any]
    ) {
        let token = runToken
        onToolStarted?(call.name)
        tool.execute(arguments: arguments) { [weak self] result in
            guard let self, self.runToken == token, self.isRunning else { return }
            self.messages.append(.tool(call: call, content: result.modelContent))
            self.onToolFinished?(call.name, result)
            self.executeNextToolCall()
        }
    }

    private func finishWithError(_ error: Error) {
        isRunning = false
        pendingCalls.removeAll()
        pendingApproval = nil
        onError?(error)
    }

    private func refreshSystemPrompt() {
        let prompt = makeSystemPrompt()
        if messages.first?.role == .system {
            messages[0].content = prompt
        } else {
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
        “可用 Skills”中的 name 只是工作流标识，不是工具名称；禁止直接调用 Skill name。
        用户任务匹配 Skill 时，只能先调用 read_skill，并将 Skill name 放入 name 参数。
        工具结果会作为 tool message 返回；根据结果继续处理，直到给出最终答复。
        不要在普通文本中伪造工具调用，不要输出“命令:”或“[命令]”协议。
        """
        return systemPromptProvider() + environment
    }
}
