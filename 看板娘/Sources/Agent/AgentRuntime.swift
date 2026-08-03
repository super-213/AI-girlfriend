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
    private let maxIterations: Int
    private var iterationCount = 0
    private var pendingCalls: [AgentToolCall] = []
    private var pendingApproval: (call: AgentToolCall, tool: any AgentTool, arguments: [String: Any])?
    private var runToken = UUID()

    init(
        apiManager: any AgentModelClient = APIManager(),
        registry: AgentToolRegistry = .standard(),
        maxIterations: Int = 8,
        systemPromptProvider: @escaping () -> String
    ) {
        self.apiManager = apiManager
        self.registry = registry
        self.maxIterations = maxIterations
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
        messages.append(.assistant(
            content: response.content.isEmpty ? nil : response.content,
            toolCalls: response.toolCalls
        ))

        guard !response.toolCalls.isEmpty else {
            isRunning = false
            onCompleted?()
            return
        }

        pendingCalls = response.toolCalls
        executeNextToolCall()
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

        if tool.requiresConfirmation {
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss EEEE XXXXX"
        let environment = """

        ## 当前运行环境
        当前本地时间：\(formatter.string(from: Date()))
        当前时区：\(TimeZone.current.identifier)

        ## 工具调用规则
        你拥有客户端提供的结构化工具。需要实时信息或外部操作时必须调用合适的工具，不要声称自己没有权限。
        工具结果会作为 tool message 返回；根据结果继续处理，直到给出最终答复。
        不要在普通文本中伪造工具调用，不要输出“命令:”或“[命令]”协议。
        """
        return systemPromptProvider() + environment
    }
}
