import Foundation
import Testing
@testable import 看板娘

struct CodexTaskMonitorTests {
    @Test func parsesWorkingAndCompletionLifecycle() throws {
        var parser = CodexRolloutParser(fallbackID: "fallback")
        parser.consume(line: json([
            "type": "session_meta",
            "payload": [
                "id": "01999999-1111-7222-8333-444444444444",
                "cwd": "/tmp/demo",
                "originator": "Codex Desktop",
                "thread_source": "user"
            ]
        ]))
        parser.consume(line: json([
            "type": "event_msg",
            "payload": ["type": "user_message", "message": "修复登录流程\n并运行测试"]
        ]))
        parser.consume(line: json([
            "type": "response_item",
            "payload": ["type": "function_call", "name": "exec_command"]
        ]))

        #expect(parser.task.phase == .working)
        #expect(parser.task.title == "修复登录流程 并运行测试")
        #expect(parser.task.currentTool == "执行命令")
        #expect(parser.task.workingDirectory == "/tmp/demo")

        let event = parser.consume(line: json([
            "type": "event_msg",
            "payload": ["type": "task_complete", "last_agent_message": "已修复，测试全部通过。"]
        ]))
        guard case .completed(let completed) = event else {
            Issue.record("应该产生 Codex 完成事件")
            return
        }
        #expect(completed.phase == .completed)
        #expect(completed.finalResponse == "已修复，测试全部通过。")
    }

    @Test func keepsWorkingAfterToolOutputAndReasoning() throws {
        var parser = CodexRolloutParser(fallbackID: "session")
        parser.consume(line: json([
            "type": "event_msg",
            "payload": ["type": "task_started"]
        ]))
        parser.consume(line: json([
            "type": "response_item",
            "payload": ["type": "custom_tool_call", "name": "apply_patch"]
        ]))
        parser.consume(line: json([
            "type": "response_item",
            "payload": ["type": "custom_tool_call_output"]
        ]))
        parser.consume(line: json([
            "type": "response_item",
            "payload": ["type": "reasoning"]
        ]))

        #expect(parser.task.phase == .working)
    }

    @Test func detectsWaitingForInputAndFiltersSubagents() throws {
        var userParser = CodexRolloutParser(fallbackID: "user")
        userParser.consume(line: json([
            "type": "response_item",
            "payload": ["type": "function_call", "name": "request_user_input"]
        ]))
        #expect(userParser.task.phase == .waitingForInput)

        var subagentParser = CodexRolloutParser(fallbackID: "subagent")
        subagentParser.consume(line: json([
            "type": "session_meta",
            "payload": ["thread_source": "subagent"]
        ]))
        subagentParser.consume(line: json([
            "type": "event_msg",
            "payload": ["type": "task_started"]
        ]))
        #expect(subagentParser.isIgnored)
        #expect(subagentParser.task.phase == .completed)
    }

    private func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
