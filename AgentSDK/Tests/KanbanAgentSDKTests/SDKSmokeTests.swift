import Foundation
import XCTest
import KanbanAgentSDK

private struct ExampleProvider: AgentModelProvider {
    let id = "example"
    let capabilities = ModelCapabilities.chatCompletions

    func streamResponse(request: ModelRequest) -> AsyncThrowingStream<ModelStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let hasToolResult = request.items.contains {
                if case .toolResult = $0 { return true }
                return false
            }
            let response = hasToolResult
                ? ModelResponse(content: "finished")
                : ModelResponse(
                    content: "",
                    toolCalls: [ToolCallItem(id: "call-1", name: "echo", arguments: #"{"text":"hello"}"#)]
                )
            continuation.yield(.completed(response))
            continuation.finish()
        }
    }
}

final class SDKSmokeTests: XCTestCase {
    func testImportedSDKCanRunCustomToolAndProvider() async throws {
        let tool = AnyAgentTool<String>(
            definition: ToolDefinition(
                name: "echo",
                description: "Echo text",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object(["text": .object(["type": .string("string")])]),
                    "required": .array([.string("text")])
                ])
            )
        ) { context, arguments in
            XCTAssertEqual(context.context, "test context")
            XCTAssertTrue(arguments.contains("hello"))
            return ToolInvocationOutput(content: "hello")
        }
        let agent = AgentDefinition<String, String>(
            id: "example",
            name: "Example",
            instructions: .fixed("Use the echo tool"),
            tools: [tool]
        )
        let run = AgentRunner(provider: ExampleProvider()).run(
            agent: agent,
            input: AgentInput("Say hello"),
            context: "test context",
            session: MemoryAgentSession()
        )
        let result = try await run.result.value
        XCTAssertEqual(result.finalOutput, "finished")
        XCTAssertTrue(result.history.contains {
            if case .toolResult = $0 { return true }
            return false
        })
    }
}
