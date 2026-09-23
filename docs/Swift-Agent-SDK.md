# KanbanAgentSDK

`KanbanAgentSDK` 位于本仓库的 [`AgentSDK`](../AgentSDK) 目录。该目录包含完整的 `Package.swift`、源码、测试和说明，可以整体复制到其他位置。它是自有实现，不是 OpenAI 官方 Agents SDK 的 Swift 移植或官方发布物。

## 引入

在另一个 Xcode 项目的 **Package Dependencies** 中选择 **Add Local…** 并指向 `AgentSDK` 目录，随后把 `KanbanAgentSDK` 产品加入目标。也可以在另一个 Swift Package 的 `Package.swift` 中使用：

```swift
dependencies: [
    .package(path: "/absolute/path/to/AgentSDK")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "KanbanAgentSDK", package: "AgentSDK")]
    )
]
```

包声明支持 macOS 15+ 与 iOS 18+。macOS 已完成编译与运行测试，iOS 已完成交叉编译，尚未在设备或模拟器上运行。看板娘应用目录中的通用 Agent 文件是指向 `AgentSDK/Sources` 的相对符号链接；真实源码只保留一份。单独复制 `AgentSDK` 时不需要复制这些应用链接。修改核心逻辑后应同时运行包测试和应用测试。

## 最小示例

```swift
import Foundation
import KanbanAgentSDK

struct MyContext: Sendable {}

let provider = OpenAIResponsesProvider(
    configuration: AgentProviderConfiguration(
        id: "openai",
        endpoint: URL(string: "https://api.openai.com/v1/responses")!,
        model: "YOUR_MODEL_ID",
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    )
)
let agent = AgentDefinition<MyContext, String>(
    id: "assistant",
    name: "Assistant",
    instructions: .fixed("You are a helpful assistant.")
)
let session = MemoryAgentSession()
let runner = AgentRunner(provider: provider)
let run = runner.run(
    agent: agent,
    input: AgentInput("Hello"),
    context: MyContext(),
    session: session
)
let result = try await run.result.value
print(result.finalOutput ?? "")
```

`run.events` 提供增量文本、工具调用、审批和完成事件。若 `result.resumableState` 非空，读取 `result.interruptions`，取得用户决定后调用 `runner.resume(agent:from:decisions:context:session:)`。`decisions` 的键是 `AgentInterruption.id`。同一 `session` 不能同时运行两个请求。

## 自定义工具与模型

实现 `AgentTool` 并用 `AnyAgentTool(yourTool)` 注册，或用 `AnyAgentTool(definition:invoke:)` 提供 JSON 参数工具。工具定义使用 `ToolDefinition` 与 `JSONValue` 描述参数；修改数据或调用外部服务时，设置合适的 `ToolBehavior` 和审批规则。

实现 `AgentModelProvider` 可接入自有模型。包自带 `OpenAIResponsesProvider`、`OpenAICompatibleChatProvider`、`ZhipuChatProvider` 和 `OllamaChatProvider`。会话可选 `MemoryAgentSession`、`PersistentAgentSession` 或自定义 `AgentSession`。桌面操作、应用权限、Keychain、UI 和看板娘内置业务工具仍由宿主应用提供。

## 验证

在 `AgentSDK` 目录运行 `swift test`。`Tests/KanbanAgentSDKTests` 作为单独模块只导入公开的 `KanbanAgentSDK` 接口，并执行自定义 Provider 与工具的完整回合。
