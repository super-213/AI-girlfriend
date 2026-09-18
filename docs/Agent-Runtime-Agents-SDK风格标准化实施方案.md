# Agent Runtime Agents SDK 风格标准化实施方案

## 1. 文档目的

本文档用于指导看板娘项目将现有自研 Swift Agent Runtime 重构为一套结构清晰、可扩展、可测试，并在核心概念和运行语义上接近 OpenAI Agents SDK 的 Agent 框架。

本次标准化的目标不是直接把 Python 或 TypeScript Agents SDK 嵌入 macOS 客户端，而是在保留 Swift、AppKit、本地桌面工具、多模型 Provider 等现有优势的前提下，对齐以下核心原语：

- Agent Definition
- Runner
- Run Context
- Run Configuration
- Run Result
- Run State
- Session
- Function Tool
- Guardrail
- Human-in-the-loop Approval
- Handoff / Agent-as-tool
- Streaming Event
- Tracing
- Model Provider

## 2. 当前实现概况

当前项目已经具备一个可工作的通用 Agent 循环，主要能力包括：

- 模型请求、工具调用、工具结果回灌和继续推理；
- 多工具注册与工具查找；
- 高风险操作人工确认；
- 会话历史保存与恢复；
- 长上下文自动及主动压缩；
- 智谱、OpenAI-Compatible/Qwen 和 Ollama Provider；
- 文件、知识库、文档、Shell、AppleScript 和 Computer Use 工具；
- 工具审计、取消生成、流式文本输出和 UI 状态反馈。

主要实现集中在：

- `看板娘/Sources/Agent/AgentRuntime.swift`
- `看板娘/Sources/Agent/AgentModels.swift`
- `看板娘/Sources/Agent/AgentTools.swift`
- `看板娘/Sources/Agent/AgentContextCompaction.swift`
- `看板娘/Sources/Services/APIManager.swift`
- `看板娘/Sources/Dialog/DialogChatViewModel.swift`
- `看板娘/Sources/Models/PetConversationSession.swift`

当前主要问题不是能力不足，而是职责边界不清：`AgentRuntime` 同时承担运行循环、会话状态、审批状态、上下文压缩和 UI 事件分发；`APIManager` 同时负责 Provider 选择、鉴权、请求构造、传输、SSE 解析和用量统计；工具参数及结果以弱类型字典和字符串为主。

## 3. 改造原则

### 3.1 保持现有功能可用

重构期间不得一次性替换现有调用链。应通过兼容适配层，让 `PetViewBackend`、`DialogChatViewModel` 和自动化入口可以逐步迁移。

### 3.2 先标准化单 Agent，再实现多 Agent

优先完成 Agent 定义、Runner、结果、Session、审批恢复和 Trace。只有当专家之间确实存在不同的指令、工具、权限或责任边界时，才引入 Handoff 或 Agent-as-tool。

### 3.3 Agent Core 不依赖具体 Provider 和 UI

Agent Core 不应直接依赖：

- `APIManager`
- SwiftUI/AppKit ViewModel
- `UserDefaults.standard`
- 全局单例 Store
- 智谱、Qwen 或 Ollama 的具体 JSON 格式

### 3.4 逐步迁移工具实现

现有工具的业务逻辑应尽量保留。先通过类型擦除适配现有 `AgentTool`，再逐个迁移为强类型异步工具。

### 3.5 保持 Provider 中立

标准化后的 Core 应支持不同能力等级的 Provider，通过能力声明进行降级，而不是把整个 Runtime 限制在 Chat Completions 的最低公共能力上。

## 4. 目标目录结构

建议最终形成以下目录：

```text
看板娘/Sources/Agent/
├── Core/
│   ├── AgentDefinition.swift
│   ├── AgentRunner.swift
│   ├── RunContext.swift
│   ├── RunConfiguration.swift
│   ├── RunResult.swift
│   ├── RunState.swift
│   ├── AgentItem.swift
│   ├── AgentRunEvent.swift
│   └── AgentError.swift
├── Sessions/
│   ├── AgentSession.swift
│   ├── MemoryAgentSession.swift
│   └── PersistentAgentSession.swift
├── Tools/
│   ├── AgentTool.swift
│   ├── AnyAgentTool.swift
│   ├── ToolContext.swift
│   ├── ToolDefinition.swift
│   └── Implementations/
├── Guardrails/
│   ├── InputGuardrail.swift
│   ├── OutputGuardrail.swift
│   ├── ToolGuardrail.swift
│   └── GuardrailResult.swift
├── Approvals/
│   ├── AgentInterruption.swift
│   ├── ApprovalDecision.swift
│   └── ApprovalPolicy.swift
├── Orchestration/
│   ├── AgentHandoff.swift
│   └── AgentAsTool.swift
├── Tracing/
│   ├── AgentTracer.swift
│   ├── AgentTrace.swift
│   └── AgentSpan.swift
├── Providers/
│   ├── AgentModelProvider.swift
│   ├── ModelCapabilities.swift
│   ├── OpenAIResponsesProvider.swift
│   ├── OpenAICompatibleChatProvider.swift
│   ├── ZhipuChatProvider.swift
│   └── OllamaChatProvider.swift
└── Compatibility/
    └── LegacyAgentRuntimeAdapter.swift
```

目录可以随实施逐步建立，不要求第一阶段一次性移动全部现有文件。

## 5. 实施顺序

## 阶段一：建立 Agent Core 基础类型

### 目标

建立标准化接口，但暂时继续复用现有 `APIManager`、`AgentToolRegistry` 和消息模型，避免在第一步同时改变运行行为。

### 5.1 新增 `AgentDefinition`

`AgentDefinition` 应作为不可变配置，集中描述一个 Agent 的固有能力：

```swift
struct AgentDefinition<Context: Sendable, Output: Sendable>: Sendable {
    let id: String
    let name: String
    let instructions: AgentInstructions<Context>
    let model: AgentModelConfiguration
    let tools: [AnyAgentTool<Context>]
    let handoffs: [AnyAgentHandoff<Context>]
    let inputGuardrails: [AnyInputGuardrail<Context>]
    let outputGuardrails: [AnyOutputGuardrail<Context, Output>]
    let outputDecoder: AgentOutputDecoder<Output>
}
```

第一版可以只实现：

- `id`
- `name`
- `instructions`
- `model`
- `tools`

其余字段先保留空实现或默认值。

### 5.2 新增 `RunContext`

将当前散落的运行依赖封装为强类型上下文：

```swift
struct AppAgentContext: Sendable {
    let conversationID: UUID
    let projectID: UUID?
    let workspacePath: String?
    let characterID: String?
    let fileAccessPolicy: AgentFileAccessPolicy
    let commandPermissionPolicy: CommandPermissionPolicy
}
```

工具不再直接从全局 Store 获取本轮上下文，而是通过 `ToolContext` 访问。

### 5.3 新增 `RunConfiguration`

至少包含：

```swift
struct RunConfiguration: Sendable {
    var maxTurns: Int = 20
    var toolTimeout: Duration = .seconds(60)
    var maximumConcurrentTools: Int = 1
    var retryPolicy: RetryPolicy = .standard
    var tracingEnabled: Bool = true
}
```

### 5.4 新增统一错误模型

建议定义：

```swift
enum AgentError: Error, Sendable {
    case busy
    case cancelled
    case maxTurnsExceeded(limit: Int)
    case modelRequestFailed(ModelProviderError)
    case invalidToolArguments(toolName: String, detail: String)
    case toolUnavailable(String)
    case toolTimedOut(String)
    case toolExecutionFailed(toolName: String, detail: String)
    case guardrailTriggered(GuardrailResult)
    case approvalStateInvalid
    case sessionFailure(String)
    case outputValidationFailed(String)
}
```

### 涉及文件

- 新增 `Agent/Core/*`
- 轻量调整 `AgentRuntime.swift`
- 扩展现有测试 Fake Model Client

### 验收标准

- 新类型可独立编译；
- 现有 Agent 功能行为不变；
- 现有测试继续通过；
- `AgentDefinition` 可以描述当前默认桌面 Agent；
- `RunConfiguration.maxTurns` 有默认值和参数校验。

---

## 阶段二：将 `AgentRuntime` 拆分为 `AgentRunner`

### 目标

让一次 `run` 明确对应一个用户轮次，Runner 只负责执行，不再长期拥有某个聊天界面的生命周期。

### 5.5 定义 Runner 接口

建议接口：

```swift
protocol AgentRunning: Sendable {
    func run<Context, Output>(
        agent: AgentDefinition<Context, Output>,
        input: AgentInput,
        context: Context,
        session: any AgentSession,
        configuration: RunConfiguration
    ) -> AgentRun<Output>
}
```

`AgentRun` 同时提供事件流和最终结果：

```swift
struct AgentRun<Output: Sendable>: Sendable {
    let events: AsyncThrowingStream<AgentRunEvent, Error>
    let result: Task<RunResult<Output>, Error>
}
```

### 5.6 迁移现有循环

将下列逻辑从 `AgentRuntime` 迁移到 `AgentRunner`：

1. 准备输入与系统指令；
2. 调用模型；
3. 解析模型输出；
4. 执行工具调用；
5. 回灌工具结果；
6. 继续模型请求；
7. 得到最终输出或中断状态；
8. 写回 Session；
9. 返回 `RunResult`。

### 5.7 增加运行边界

必须加入：

- `maxTurns`；
- Task cancellation；
- 工具执行 timeout；
- 模型请求 timeout；
- 可配置重试；
- 重试时防止重复执行非幂等工具。

当前“超过 17 次工具调用仍继续”的测试需要调整为两类测试：

- 在限制内可以正常继续；
- 超过 `maxTurns` 后返回 `maxTurnsExceeded`。

### 5.8 从 `@MainActor` 中移出执行循环

`AgentRunner` 建议实现为独立 `actor` 或完全基于 Swift Concurrency 的可发送类型。网络、模型解析和工具调度不应占用主 Actor。

UI 只在消费 `AgentRunEvent` 时切换到 `MainActor`。

### 涉及文件

- 新增 `Agent/Core/AgentRunner.swift`
- 新增 `Agent/Core/AgentRunEvent.swift`
- 修改 `AgentRuntime.swift` 为兼容包装器
- 修改 `DialogChatViewModel.swift`
- 修改 `PetViewBackend.swift`
- 更新 `看板娘Tests/___Tests.swift`

### 验收标准

- 一次用户输入对应一个 Runner run；
- 连续工具调用仍能正确完成；
- 达到最大轮次后明确终止；
- 取消后不再产生后续 UI 或工具副作用；
- 运行循环不要求整体位于 `MainActor`；
- 现有 UI 暂时可通过兼容适配层正常工作。

---

## 阶段三：引入 `RunResult`、`RunState` 和统一事件流

### 目标

用结构化结果代替分散的完成闭包，并为暂停、审批和恢复建立稳定数据模型。

### 5.9 定义 `RunResult`

```swift
struct RunResult<Output: Sendable>: Sendable {
    let finalOutput: Output?
    let history: [AgentItem]
    let newItems: [AgentItem]
    let lastAgentID: String
    let usage: AgentUsage
    let rawResponses: [ModelResponse]
    let guardrailResults: [GuardrailResult]
    let interruptions: [AgentInterruption]
    let resumableState: RunState?
}
```

### 5.10 定义标准化 `AgentItem`

避免继续把所有运行数据压缩成 `AgentMessage`：

```swift
enum AgentItem: Codable, Sendable {
    case message(AgentMessageItem)
    case toolCall(ToolCallItem)
    case toolResult(ToolResultItem)
    case handoff(HandoffItem)
    case guardrail(GuardrailItem)
    case approval(ApprovalItem)
    case compaction(CompactionItem)
}
```

Provider Adapter 负责将 `AgentItem` 转换为各自 API 需要的消息或响应项。

### 5.11 定义统一事件流

```swift
enum AgentRunEvent: Sendable {
    case runStarted(RunSnapshot)
    case agentStarted(AgentSnapshot)
    case modelStarted(ModelRequestSnapshot)
    case textDelta(String)
    case modelCompleted(ModelResponseSnapshot)
    case toolCallStarted(ToolCallItem)
    case toolCallCompleted(ToolResultItem)
    case approvalRequired(AgentInterruption)
    case handoff(HandoffEvent)
    case contextCompactionStarted
    case contextCompacted(CompactionEvent)
    case usageUpdated(AgentUsage)
    case runCompleted
    case runFailed(AgentError)
}
```

### 5.12 兼容现有 UI 回调

`LegacyAgentRuntimeAdapter` 暂时把事件流转换为：

- `onAssistantResponseStarted`
- `onAssistantText`
- `onToolStarted`
- `onToolFinished`
- `onApprovalRequested`
- `onContextCompacted`
- `onCompleted`
- `onError`

UI 全部迁移完成后再移除旧闭包接口。

### 验收标准

- 最终结果可通过 `RunResult` 获取；
- UI 不需要读取 Runner 内部私有状态；
- 事件顺序可在测试中稳定断言；
- 每次 run 都有唯一 run ID；
- 中途取消、错误和审批暂停均有明确事件与结果。

---

## 阶段四：工具强类型化与异步化

### 目标

逐步消除 `[String: Any]` 和 completion callback，使工具具备类型安全、Schema 校验、取消和并发能力。

### 5.13 定义强类型工具协议

```swift
protocol AgentTool: Sendable {
    associatedtype Context: Sendable
    associatedtype Arguments: Codable & Sendable
    associatedtype Output: Codable & Sendable

    static var name: String { get }
    static var description: String { get }
    static var behavior: ToolBehavior { get }

    func invoke(
        context: ToolContext<Context>,
        arguments: Arguments
    ) async throws -> Output
}
```

`ToolBehavior` 应描述：

- 是否只读；
- 是否幂等；
- 是否可能产生外部副作用；
- 默认是否需要审批；
- 是否允许并发；
- 默认 timeout；
- 失败后能否自动重试。

### 5.14 增加类型擦除

Runner 使用 `AnyAgentTool<Context>` 保存不同参数和输出类型的工具。

类型擦除层负责：

- JSON Schema 暴露；
- 参数 JSON 解码；
- 参数校验；
- 调用具体工具；
- 输出编码；
- 错误标准化。

### 5.15 提供旧工具适配器

在迁移完成前提供：

```swift
LegacyToolAdapter(existingTool: oldTool)
```

建议迁移顺序：

1. `get_current_datetime`
2. `list_directory`
3. `read_file`
4. `search_files`
5. `open_application`
6. 文件写入、复制和移动工具
7. Shell 与 AppleScript 工具
8. 文档生成工具
9. Knowledge Base 工具
10. Computer Use 工具

先迁移只读、参数简单的工具，再迁移带副作用和复杂状态的工具。

### 5.16 并发工具策略

当前多个工具调用按顺序执行。新 Runtime 可以支持受控并发，但只有满足以下条件才并发：

- Provider 支持并行工具调用；
- 工具声明 `allowsParallelExecution`；
- 工具之间不存在资源冲突；
- 工具无需等待人工审批；
- 工具为只读或可以证明安全幂等。

写文件、移动文件、Computer Use、Shell 和 AppleScript 默认串行。

### 验收标准

- 新工具不使用 `[String: Any]` 作为公开参数接口；
- 参数不合法时不会进入工具业务逻辑；
- 工具支持 Task cancellation 和 timeout；
- 工具输出可编码为结构化结果；
- 旧工具与新工具可以同时注册；
- 非幂等工具不会被自动重复执行。

---

## 阶段五：统一 Session 和持久化

### 目标

把完整对话、桌宠临时会话、审批状态和上下文压缩历史统一到 Session 抽象下。

### 5.17 定义 `AgentSession`

```swift
protocol AgentSession: Sendable {
    var id: String { get }

    func loadItems() async throws -> [AgentItem]
    func append(_ items: [AgentItem]) async throws
    func replaceItems(_ items: [AgentItem]) async throws
    func loadRunState() async throws -> RunState?
    func saveRunState(_ state: RunState?) async throws
}
```

### 5.18 Session 实现

第一批实现：

- `MemoryAgentSession`：测试、一次性自动化、临时任务；
- `PersistentAgentSession`：完整对话窗口；
- `ExpiringAgentSession`：桌宠气泡的超时会话。

### 5.19 迁移现有数据

需要兼容：

- `DialogConversation.agentHistory`
- `PetConversationSession.history`
- 旧版 `[AgentMessage]` 编码数据

建议为持久化数据增加：

- `schemaVersion`
- `sessionID`
- `createdAt`
- `updatedAt`
- `agentID`
- `providerConfigurationID`
- `items`
- `pendingRunState`

读取旧版数据时转换为 `AgentItem.message`，保存时写入新版本。

### 5.20 会话并发控制

同一 Session 同一时间默认只允许一个活动 run。需要排队时由上层 Message Queue 负责，不在 Runner 内部静默覆盖状态。

### 验收标准

- 现有对话历史可以无损读取；
- 新旧会话可以正常切换；
- 桌宠会话超时行为保持不变；
- App 重启后可以恢复待审批 run；
- Session 写入失败不会丢失当前内存结果；
- 同一 Session 不会发生并发写入覆盖。

---

## 阶段六：审批改为可恢复的 Interruption

### 目标

将当前内存中的单个 `pendingApproval` 改造成可序列化、支持多个待审批项、可以跨 App 生命周期恢复的暂停状态。

### 5.21 定义中断和决策

```swift
struct AgentInterruption: Codable, Sendable, Identifiable {
    let id: UUID
    let runID: UUID
    let toolCall: ToolCallItem
    let summary: String
    let riskLevel: RiskLevel
    let requestedAt: Date
}

enum ApprovalDecision: Codable, Sendable {
    case approved
    case rejected(reason: String?)
}
```

### 5.22 定义可序列化 `RunState`

`RunState` 至少保存：

- run ID；
- 当前 Agent ID；
- turn 数；
- 已完成 items；
- 待执行工具；
- 待审批 interruption；
- Context compaction 状态；
- Provider continuation ID（如果有）；
- trace ID；
- Session ID。

禁止在 `RunState` 中直接保存无法编码的工具实例、闭包、ViewModel 或 Store 引用。

### 5.23 恢复同一次 run

审批后调用：

```swift
let resumed = runner.resume(
    from: state,
    decisions: decisions,
    context: appContext,
    session: session
)
```

审批恢复必须继续原 run，而不是创建一条伪造的新用户消息。

### 验收标准

- 审批等待期间可以关闭并重新打开对话；
- App 重启后能够显示待审批操作；
- 批准和拒绝都能继续原 run；
- 已完成的非幂等工具不会重复执行；
- 状态版本不兼容时安全失败，而不是执行不确定动作。

---

## 阶段七：拆分 Model Provider 与 `APIManager`

### 目标

让 Runner 面向统一模型协议编程，把各 Provider 的请求格式、鉴权和流式解析隔离在 Adapter 中。

### 5.24 定义 Provider 协议

```swift
protocol AgentModelProvider: Sendable {
    var id: String { get }
    var capabilities: ModelCapabilities { get }

    func streamResponse(
        request: ModelRequest
    ) -> AsyncThrowingStream<ModelStreamEvent, Error>
}
```

### 5.25 定义 Provider 能力

```swift
struct ModelCapabilities: Sendable {
    let supportsTools: Bool
    let supportsParallelTools: Bool
    let supportsStructuredOutput: Bool
    let supportsImageInput: Bool
    let supportsServerManagedState: Bool
    let supportsPromptCaching: Bool
    let supportsResponsesAPI: Bool
}
```

### 5.26 拆分 Adapter

- `OpenAIResponsesProvider`
- `OpenAICompatibleChatProvider`
- `ZhipuChatProvider`
- `OllamaChatProvider`

Runner 只处理：

- `ModelRequest`
- `ModelStreamEvent`
- `ModelResponse`
- `AgentItem`

不再识别 `choices.delta.tool_calls`、Ollama `message.tool_calls` 等具体 JSON。

### 5.27 缩减 `APIManager`

迁移完成后，`APIManager` 可以：

- 仅保留旧聊天接口；或
- 改造成 Provider Factory / Configuration Resolver；或
- 完全由新的 Provider 层取代。

API Key 继续由现有 Keychain 机制管理。

### 验收标准

- Runner 测试不需要实例化 `APIManager`；
- 每个 Provider 有独立序列化和流式解析测试；
- Provider 不支持某能力时返回明确能力错误或安全降级；
- Qwen、智谱和 Ollama 的现有功能保持可用；
- OpenAI Provider 可以独立采用 Responses API 语义。

---

## 阶段八：Guardrails 与结构化输出

### 目标

把输入检查、输出检查、工具权限和副作用控制变成 Runner 的一等能力。

### 5.28 Input Guardrail

在主模型运行前检查：

- 请求是否为空或无效；
- 文件、目录和项目上下文是否合法；
- 是否违反应用安全策略；
- 是否缺少完成任务必须的权限。

### 5.29 Tool Guardrail

在工具执行前后检查：

- 调用参数是否越权；
- 文件路径是否在授权范围；
- 命令是否满足权限策略；
- Computer Use 操作目标是否与用户任务一致；
- 是否需要人工确认；
- 工具结果是否包含敏感信息。

现有 `requiresConfirmation`、文件访问控制和命令权限策略应逐步迁入这一层。

### 5.30 Output Guardrail

在结果展示给用户前检查：

- 结构化输出是否有效；
- 是否包含不应展示的敏感数据；
- 是否错误声明操作成功；
- 是否需要补充失败或未验证提示。

### 5.31 Structured Output

为 Agent 增加泛型 Output 和 decoder。字符串回答仍使用 `String`，结构化任务可以使用 Codable 类型，例如：

```swift
struct FileOrganizationPlan: Codable, Sendable {
    let operations: [FileOperation]
    let warnings: [String]
}
```

### 验收标准

- Guardrail 可以停止、暂停或允许 run；
- Guardrail 结果进入 `RunResult` 和 Trace；
- 工具权限检查不依赖模型是否遵守提示词；
- 结构化输出解析失败时不会把无效数据交给业务层；
- 高风险动作继续保持人在回路确认。

---

## 阶段九：Tracing 与可观测性

### 目标

从当前工具级审计扩展为覆盖整个 Agent run 的结构化 Trace。

### 5.32 Trace 层级

```text
Trace
└── Run Span
    ├── Agent Span
    ├── Model Span
    ├── Tool Span
    ├── Guardrail Span
    ├── Approval Span
    ├── Handoff Span
    └── Compaction Span
```

### 5.33 标准字段

每个 Span 至少记录：

- trace ID、span ID、parent span ID；
- run ID、session ID、Agent ID；
- 类型和名称；
- 开始时间、结束时间、耗时；
- `running/completed/failed/interrupted/cancelled` 状态；
- Provider 和模型；
- token 用量；
- 工具参数及输出的脱敏摘要；
- 审批决定；
- 重试次数和标准化错误。

### 5.34 Tracer 接口

```swift
protocol AgentTracer: Sendable {
    func startSpan(_ definition: SpanDefinition) async -> SpanHandle
    func record(_ event: TraceEvent, in span: SpanHandle) async
    func endSpan(_ span: SpanHandle, outcome: SpanOutcome) async
}
```

第一版提供本地 Tracer，后续可以增加 OTLP 或其他导出器。

### 5.35 与现有审计融合

`AgentToolAuditStore` 可以继续作为用户可见审计数据源，但数据应由 Tool Span 映射产生，避免 Runner 和工具分别重复写两套日志。

### 验收标准

- 每个 run 都能重建执行时间线；
- 模型请求、工具、审批和压缩都有父子关系；
- Trace 不保存 API Key、完整敏感文件内容或未脱敏命令输出；
- Trace 写入失败不影响正常 run；
- 测试可以使用 In-Memory Tracer 断言 span 顺序。

---

## 阶段十：Handoff、Agent-as-tool 和 MCP

### 目标

在单 Agent Runtime 稳定后，引入多 Agent 编排和外部工具协议。

### 5.36 优先实现 Agent-as-tool

推荐初始结构：

```text
Desktop Companion Agent
├── Document Agent
├── Knowledge Base Agent
├── Computer Use Agent
└── Automation Agent
```

主 Agent 保持最终回复责任，专家 Agent 只完成边界明确的子任务。

适合 Agent-as-tool 的场景：

- 文档抽取和摘要；
- 知识库检索与答案整理；
- 操作计划生成；
- 自动化选择；
- 文件组织方案生成。

### 5.37 再实现 Handoff

只有当专家应当接管后续对话时才使用 Handoff，例如：

- 进入持续的 Computer Use 操作模式；
- 进入某个项目专属 Agent；
- 不同 Agent 具有明显不同的权限策略。

Handoff 需要记录：

- 来源和目标 Agent；
- handoff 原因；
- 传递或过滤后的历史；
- 结构化 metadata；
- 后续 turn 默认由哪个 Agent 负责。

### 5.38 MCP 抽象

定义：

- `MCPServerConfiguration`
- `MCPToolProvider`
- `MCPApprovalPolicy`
- `MCPToolFilter`

本地或私有 MCP 连接必须继续由应用控制权限、网络边界和审批策略。

### 验收标准

- 单 Agent 模式不依赖任何多 Agent 组件；
- 专家 Agent 只能看到其需要的工具和上下文；
- Agent-as-tool 的输出作为结构化工具结果返回主 Agent；
- Handoff 后 `RunResult.lastAgentID` 正确；
- MCP 工具遵守统一 Tool Guardrail 和 Approval Policy；
- 所有编排行为进入 Trace。

## 6. 测试计划

每一阶段都应同时增加测试，不能等到全部重构结束后再补。

### 6.1 Core 单元测试

- Agent 定义默认值和动态 instructions；
- Runner 最终输出；
- 多轮工具循环；
- 最大 turn 限制；
- 取消和 timeout；
- 工具参数校验；
- Provider 能力降级；
- 结构化输出解析。

### 6.2 Session 测试

- 历史读写；
- 旧版消息迁移；
- Session 过期；
- 同 Session 并发冲突；
- RunState 保存与恢复；
- App 重启后的审批恢复。

### 6.3 安全测试

- 越权路径访问被阻止；
- 风险命令触发审批；
- 拒绝后工具不执行；
- 恢复时非幂等工具不重复；
- Guardrail 故障时 fail closed；
- Trace 和错误信息不会泄露 API Key。

### 6.4 Provider 契约测试

同一组 Runner 行为测试应可以在 Fake Provider 和各真实 Provider Adapter 上运行：

- 文本流；
- 单工具调用；
- 多工具调用；
- 工具参数分片；
- usage-only chunk；
- Provider 错误；
- 流中断；
- 多模态消息；
- 不支持能力的降级。

### 6.5 UI 回归测试

- 桌宠 thinking/working/waiting/success/error 状态；
- Ctrl+T 对话流式更新；
- 停止生成；
- 工具确认卡片；
- 切换会话；
- 消息队列；
- Context compaction 提示；
- 重启后恢复审批。

## 7. 兼容和迁移策略

### 7.1 保留旧入口

第一至第五阶段保留现有：

```swift
AgentRuntime.send(...)
AgentRuntime.approvePendingTool()
AgentRuntime.declinePendingTool()
AgentRuntime.cancel()
```

这些入口由 `LegacyAgentRuntimeAdapter` 转发给新 Runner。

### 7.2 双格式读取、单格式写入

会话迁移期间：

- 支持读取旧 `[AgentMessage]`；
- 内部转换为 `[AgentItem]`；
- 只写入带 `schemaVersion` 的新格式；
- 必要时保留一次备份，避免迁移失败导致历史丢失。

### 7.3 分工具迁移

不要一次修改所有工具。Registry 同时接受：

- 新的 `AnyAgentTool`；
- 经 `LegacyToolAdapter` 包装的旧工具。

当所有工具完成迁移后，再删除旧 `AgentTool` 协议。

### 7.4 分入口迁移

建议顺序：

1. 单元测试与 Fake Provider；
2. 完整对话窗口；
3. 桌宠主窗口；
4. 自动化触发；
5. 外部控制服务；
6. Computer Use 长任务。

## 8. 完成定义

当满足以下条件时，可以认为 Agents SDK 风格标准化完成：

- Agent 配置与 Runner 执行完全分离；
- Runner 不依赖具体 UI 或 Provider；
- 一次 run 返回结构化 `RunResult`；
- Session 负责多轮状态和持久化；
- 审批可以序列化、持久化和恢复；
- 所有新工具使用强类型 `async throws` 接口；
- Guardrail 可以控制输入、输出和工具行为；
- Provider 通过统一协议和能力声明接入；
- 运行过程使用统一事件流；
- 模型、工具、审批、压缩和 Handoff 都有 Trace；
- Runner 有最大 turn、timeout、取消和安全重试限制；
- 至少支持 Agent-as-tool；
- 现有智谱、Qwen/OpenAI-Compatible 和 Ollama 能力没有回退；
- 旧会话数据可以兼容迁移；
- UI、自动化和桌面工具通过新 Runtime 正常运行。

## 9. 建议优先交付的最小版本

如果需要先完成一个可合并、风险较低的版本，建议仅包含：

1. `AgentDefinition`；
2. `RunConfiguration`；
3. `AgentRunner`；
4. `RunResult`；
5. `AgentRunEvent`；
6. `maxTurns` 和统一错误类型；
7. `LegacyAgentRuntimeAdapter`；
8. 对应单元测试。

该最小版本不修改 Provider、不迁移具体工具、不增加多 Agent，但会先建立后续所有改造依赖的稳定边界。

## 10. 参考资料

- OpenAI Agents SDK — Agent definitions：<https://developers.openai.com/api/docs/guides/agents/define-agents>
- OpenAI Agents SDK — Running agents：<https://developers.openai.com/api/docs/guides/agents/running-agents>
- OpenAI Agents SDK — Tools：<https://developers.openai.com/api/docs/guides/tools>
- OpenAI Agents SDK — Results and state：<https://developers.openai.com/api/docs/guides/agents/results>
- OpenAI Agents SDK — Guardrails and human review：<https://developers.openai.com/api/docs/guides/agents/guardrails-approvals>
- OpenAI Agents SDK — Orchestration and handoffs：<https://developers.openai.com/api/docs/guides/agents/orchestration>
- OpenAI Agents SDK — Integrations and observability：<https://developers.openai.com/api/docs/guides/agents/integrations-observability>
