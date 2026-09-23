# KanbanAgentSDK

这是一个可独立复制的 Swift Package。把整个 `AgentSDK` 目录复制到其他位置，即可通过 Swift Package Manager 引入；包内没有指向看板娘应用目录的源码路径。

支持 macOS 15+ 与 iOS 18+。提供 Agent 运行器、工具、Provider、会话、审批、Guardrail、Handoff、MCP 协议和追踪。看板娘的桌面控制、UI、Keychain 和业务工具不属于本包。

在另一个 Swift Package 中添加本地依赖：

```swift
dependencies: [.package(path: "/path/to/AgentSDK")],
targets: [
    .target(
        name: "YourApp",
        dependencies: [.product(name: "KanbanAgentSDK", package: "AgentSDK")]
    )
]
```

然后在 Swift 文件中 `import KanbanAgentSDK`。最小用法：

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
let run = AgentRunner(provider: provider).run(
    agent: agent,
    input: AgentInput("Hello"),
    context: MyContext(),
    session: MemoryAgentSession()
)
let result = try await run.result.value
print(result.finalOutput ?? "")
```

自定义工具可实现 `AgentTool` 并用 `AnyAgentTool` 注册；自定义模型可实现 `AgentModelProvider`。`run.events` 提供运行事件。遇到审批时，从 `result.interruptions` 取得请求、用 `result.resumableState` 保存状态，再用 `AgentRunner.resume` 和以请求 ID 为键的决定恢复。

在此目录运行 `swift test` 验证独立包。
