//
//  AgentContextCompaction.swift
//  看板娘
//
//  Provider-neutral context compaction inspired by long-running coding agents.
//

import Foundation

struct AgentContextCompactionPolicy: Equatable {
    /// Compact before a conservative 32K-class context becomes crowded.
    var triggerTokenCount: Int = 24_000
    /// Leave enough room for tool work and the model's next response.
    var targetTokenCount: Int = 12_000
    var summaryTokenReserve: Int = 2_000
    var maximumToolResultCharacters: Int = 12_000
    var maximumSummaryInputCharacters: Int = 20_000

    static let standard = AgentContextCompactionPolicy()
}

struct AgentContextMeasurement: Equatable {
    let estimatedTokens: Int
    let measuredTokens: Int
}

struct AgentContextCompactionPlan: Equatable {
    let messagesToSummarize: [AgentMessage]
    let recentMessages: [AgentMessage]
    let estimatedTokensBeforeCompaction: Int
}

struct AgentContextCompactionEvent: Equatable {
    let summarizedMessageCount: Int
    let retainedMessageCount: Int
    let estimatedTokensBeforeCompaction: Int
}

struct AgentContextManager {
    let policy: AgentContextCompactionPolicy

    init(policy: AgentContextCompactionPolicy = .standard) {
        self.policy = policy
    }

    func estimatedTokenCount(
        messages: [AgentMessage],
        tools: [AgentToolDefinition]
    ) -> Int {
        let messageBytes = messages.reduce(0) { partial, message in
            partial + estimatedByteCount(for: message) + 24
        }
        let toolBytes = tools.reduce(0) { partial, tool in
            guard JSONSerialization.isValidJSONObject(tool.jsonObject()),
                  let data = try? JSONSerialization.data(withJSONObject: tool.jsonObject()) else {
                return partial + tool.name.utf8.count + tool.description.utf8.count + 64
            }
            return partial + data.count
        }
        // Chinese text is commonly denser than four UTF-8 bytes per token. Three
        // bytes is deliberately conservative and the measured usage corrects it.
        return max(Int(ceil(Double(messageBytes + toolBytes) / 3.0)), 1)
    }

    func projectedTokenCount(
        messages: [AgentMessage],
        tools: [AgentToolDefinition],
        previousMeasurement: AgentContextMeasurement?
    ) -> Int {
        let estimated = estimatedTokenCount(messages: messages, tools: tools)
        guard let previousMeasurement else { return estimated }
        let growth = max(estimated - previousMeasurement.estimatedTokens, 0)
        return max(estimated, previousMeasurement.measuredTokens + growth)
    }

    func makePlan(
        messages: [AgentMessage],
        tools: [AgentToolDefinition],
        previousMeasurement: AgentContextMeasurement? = nil
    ) -> AgentContextCompactionPlan? {
        let projectedTokens = projectedTokenCount(
            messages: messages,
            tools: tools,
            previousMeasurement: previousMeasurement
        )
        guard projectedTokens >= policy.triggerTokenCount,
              let firstSystemIndex = messages.firstIndex(where: { $0.role == .system && $0.contextKind == nil }) else {
            return nil
        }

        let bodyStart = messages.index(after: firstSystemIndex)
        guard bodyStart < messages.endIndex else { return nil }
        let units = conversationUnits(in: messages, from: bodyStart)
        guard units.count >= 2 else { return nil }

        let fixedMessages = [messages[firstSystemIndex]]
        let fixedTokens = estimatedTokenCount(messages: fixedMessages, tools: tools)
        let recentBudget = max(
            policy.targetTokenCount - fixedTokens - policy.summaryTokenReserve,
            1
        )

        var keptRanges: [Range<Int>] = []
        var keptTokens = 0
        for range in units.reversed() {
            let unit = Array(messages[range])
            let unitTokens = estimatedTokenCount(messages: unit, tools: [])
            if !keptRanges.isEmpty, keptTokens + unitTokens > recentBudget {
                break
            }
            keptRanges.append(range)
            keptTokens += unitTokens
        }

        guard let keepStart = keptRanges.map(\.lowerBound).min(), keepStart > bodyStart else {
            return nil
        }
        let older = Array(messages[bodyStart..<keepStart])
        let recent = Array(messages[keepStart...])
        guard !older.isEmpty, !recent.isEmpty else { return nil }

        return AgentContextCompactionPlan(
            messagesToSummarize: older,
            recentMessages: recent,
            estimatedTokensBeforeCompaction: projectedTokens
        )
    }

    func summaryRequestMessages(for plan: AgentContextCompactionPlan) -> [AgentMessage] {
        let transcript = summaryTranscript(from: plan.messagesToSummarize)
        return [
            .system(Self.summarySystemPrompt),
            .user(transcript)
        ]
    }

    func compactedMessages(
        systemMessage: AgentMessage,
        summary: String,
        plan: AgentContextCompactionPlan
    ) -> [AgentMessage] {
        let summaryMessage = AgentMessage.contextSummary("""
        ## 压缩后的会话上下文
        以下是对更早对话和工具结果的自动压缩。将其视为已发生的会话状态，不要声称刚刚执行了其中的操作。

        \(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        """)
        return [systemMessage, summaryMessage] + plan.recentMessages
    }

    /// Tool output is the least stable and often the largest part of an agent
    /// context. Keep the beginning and end so one observation cannot consume
    /// the entire context window before the next compaction pass.
    func boundedToolResult(_ content: String) -> String {
        truncatedMiddle(content, limit: policy.maximumToolResultCharacters)
    }

    private func conversationUnits(
        in messages: [AgentMessage],
        from bodyStart: Int
    ) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var unitStart = bodyStart

        for index in bodyStart..<messages.endIndex {
            guard messages[index].role == .user, index > unitStart else { continue }
            ranges.append(unitStart..<index)
            unitStart = index
        }
        ranges.append(unitStart..<messages.endIndex)
        return ranges.filter { !$0.isEmpty }
    }

    private func summaryTranscript(from messages: [AgentMessage]) -> String {
        let rendered = messages.enumerated().map { index, message in
            let role: String
            if message.contextKind == .compactionSummary {
                role = "PREVIOUS_COMPACTION_SUMMARY"
            } else {
                role = message.role.rawValue.uppercased()
            }

            var parts = ["[\(index + 1)] \(role)"]
            if let content = message.content, !content.isEmpty {
                let limit = message.role == .tool
                    ? policy.maximumToolResultCharacters
                    : policy.maximumSummaryInputCharacters
                parts.append(truncated(content, limit: limit))
            }
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                let calls = toolCalls.map { call in
                    "\(call.name)(\(truncated(call.arguments, limit: 4_000)))"
                }.joined(separator: "\n")
                parts.append("TOOL_CALLS:\n\(calls)")
            }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n")

        return truncatedMiddle(rendered, limit: policy.maximumSummaryInputCharacters)
    }

    private func estimatedByteCount(for message: AgentMessage) -> Int {
        var count = message.role.rawValue.utf8.count
        count += message.content?.utf8.count ?? 0
        count += message.toolCallID?.utf8.count ?? 0
        count += message.name?.utf8.count ?? 0
        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                count += call.id.utf8.count + call.name.utf8.count + call.arguments.utf8.count + 32
            }
        }
        return count
    }

    private func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "\n…[较长内容已在压缩输入中截断]"
    }

    private func truncatedMiddle(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let headCount = max(limit * 2 / 5, 1)
        let tailCount = max(limit - headCount, 1)
        return String(value.prefix(headCount))
            + "\n\n…[为控制上下文长度，中部内容已省略]…\n\n"
            + String(value.suffix(tailCount))
    }

    private static let summarySystemPrompt = """
    你是 Agent 会话压缩器。将较早的会话与工具输出改写为可供后续 Agent 继续工作的结构化交接摘要。

    必须保留：
    - 用户的核心目标、明确要求、偏好和禁止项
    - 已确认的事实、决策、假设和重要解释
    - 已完成的工作、文件路径、修改、命令和验证结果
    - 关键工具结果、错误、失败尝试及其原因
    - 未完成任务、当前状态、阻塞项和明确的下一步

    删除寒暄、重复解释、已被后续结论取代的中间推测，以及无需保留的大段原始输出。
    不得编造事实，不得将计划写成已完成。

    仅输出 Markdown 摘要，使用以下标题：
    ## 用户目标与约束
    ## 已知事实与决策
    ## 已完成工作
    ## 当前状态与未完成项
    ## 关键参考
    """
}
