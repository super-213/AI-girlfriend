//
//  CodexTaskMonitor.swift
//  看板娘
//
//  Read-only Codex CLI/Desktop rollout watcher. It never changes Codex config.
//

import Combine
import Foundation

enum CodexTaskPhase: String, Codable, Sendable {
    case thinking
    case working
    case waitingForInput
    case completed
    case aborted
    case failed

    var isActive: Bool {
        switch self {
        case .thinking, .working, .waitingForInput: return true
        case .completed, .aborted, .failed: return false
        }
    }

    var displayName: String {
        switch self {
        case .thinking: return "思考中"
        case .working: return "执行中"
        case .waitingForInput: return "等待回复"
        case .completed: return "已完成"
        case .aborted: return "已中断"
        case .failed: return "执行失败"
        }
    }
}

struct CodexTaskSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var workingDirectory: String?
    var originator: String?
    var phase: CodexTaskPhase
    var currentTool: String?
    var finalResponse: String?
    var updatedAt: Date
}

enum CodexTaskMonitorEvent: Equatable, Sendable {
    case completed(CodexTaskSnapshot)
    case aborted(CodexTaskSnapshot)
    case failed(CodexTaskSnapshot)
}

/// Stateful parser kept separate from file watching so rollout schema handling
/// can be covered with deterministic tests.
struct CodexRolloutParser: Sendable {
    private(set) var task: CodexTaskSnapshot
    private(set) var isIgnored = false
    private var didWorkThisTurn = false
    private var lastAgentMessage: String?

    init(fallbackID: String, now: Date = .now) {
        task = CodexTaskSnapshot(
            id: fallbackID,
            title: "Codex 任务",
            workingDirectory: nil,
            originator: nil,
            phase: .completed,
            currentTool: nil,
            finalResponse: nil,
            updatedAt: now
        )
    }

    @discardableResult
    mutating func consume(line: String, observedAt: Date = .now) -> CodexTaskMonitorEvent? {
        guard let data = line.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = root["type"] as? String,
              let payload = root["payload"] as? [String: Any] else { return nil }

        if type == "session_meta" {
            applyMetadata(payload)
            return nil
        }
        guard !isIgnored else { return nil }

        task.updatedAt = observedAt
        if type == "response_item" {
            return consumeResponseItem(payload)
        }
        guard type == "event_msg", let eventType = payload["type"] as? String else { return nil }

        if eventType == "item_completed", let item = payload["item"] as? [String: Any] {
            consumeCompletedItem(item)
            return nil
        }

        switch eventType {
        case "user_message":
            if let message = payload["message"] as? String { task.title = Self.title(from: message) }
            beginTurn()
        case "task_started":
            beginTurn()
        case "agent_message":
            if let message = payload["message"] as? String, !message.isEmpty {
                lastAgentMessage = message
            }
        case "task_complete":
            task.phase = .completed
            task.currentTool = nil
            task.finalResponse = Self.clipped(
                (payload["last_agent_message"] as? String) ?? lastAgentMessage,
                limit: 5_000
            )
            didWorkThisTurn = false
            return .completed(task)
        case "turn_aborted":
            task.phase = .aborted
            task.currentTool = nil
            didWorkThisTurn = false
            return .aborted(task)
        case "context_compacted", "compacted":
            task.phase = .thinking
            task.currentTool = "整理上下文"
        case "patch_apply_end":
            markWorking(tool: "编辑文件")
        case "mcp_tool_call_end":
            let invocation = payload["invocation"] as? [String: Any]
            markWorking(tool: invocation?["tool"] as? String ?? "MCP 工具")
        case "web_search_end":
            markWorking(tool: "网页搜索")
        case "agent_reasoning":
            task.phase = didWorkThisTurn ? .working : .thinking
        case "error", "stream_error":
            task.phase = .failed
            task.currentTool = nil
            task.finalResponse = payload["message"] as? String
            return .failed(task)
        default:
            if eventType.hasSuffix("approval_request")
                || eventType == "request_user_input"
                || eventType == "elicitation_request" {
                task.phase = .waitingForInput
                task.currentTool = nil
            }
        }
        return nil
    }

    private mutating func applyMetadata(_ payload: [String: Any]) {
        if let id = (payload["id"] as? String) ?? (payload["session_id"] as? String), !id.isEmpty {
            task.id = id
        }
        task.workingDirectory = payload["cwd"] as? String
        task.originator = payload["originator"] as? String
        let source = payload["source"] as? [String: Any]
        isIgnored = payload["thread_source"] as? String == "subagent" || source?["subagent"] != nil
    }

    private mutating func consumeResponseItem(_ payload: [String: Any]) -> CodexTaskMonitorEvent? {
        guard let itemType = payload["type"] as? String else { return nil }
        switch itemType {
        case "function_call", "custom_tool_call":
            let name = payload["name"] as? String ?? "工具"
            if name == "request_user_input" {
                task.phase = .waitingForInput
                task.currentTool = nil
            } else {
                markWorking(tool: Self.displayToolName(name))
            }
        case "web_search_call":
            markWorking(tool: "网页搜索")
        case "function_call_output", "custom_tool_call_output":
            didWorkThisTurn = true
            task.phase = .working
        case "reasoning":
            task.phase = didWorkThisTurn ? .working : .thinking
        case "message":
            if payload["role"] as? String == "assistant",
               payload["phase"] as? String == "final_answer" {
                let text = Self.contentText(payload["content"])
                if !text.isEmpty { lastAgentMessage = text }
            }
        default:
            break
        }
        return nil
    }

    private mutating func consumeCompletedItem(_ item: [String: Any]) {
        switch item["type"] as? String {
        case "UserMessage":
            let text = Self.contentText(item["content"])
            if !text.isEmpty { task.title = Self.title(from: text) }
            beginTurn()
        case "AgentMessage":
            if item["phase"] as? String == "final_answer" {
                let text = Self.contentText(item["content"])
                if !text.isEmpty { lastAgentMessage = text }
            }
        case "SubAgentActivity":
            if item["kind"] as? String == "started" {
                markWorking(tool: "子任务")
            }
        default:
            break
        }
    }

    private mutating func beginTurn() {
        didWorkThisTurn = false
        lastAgentMessage = nil
        task.finalResponse = nil
        task.currentTool = nil
        task.phase = .thinking
    }

    private mutating func markWorking(tool: String) {
        didWorkThisTurn = true
        task.phase = .working
        task.currentTool = tool
    }

    private static func contentText(_ value: Any?) -> String {
        guard let blocks = value as? [[String: Any]] else { return "" }
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private static func title(from text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "Codex 任务" }
        return singleLine.count > 48 ? String(singleLine.prefix(48)) + "…" : singleLine
    }

    private static func clipped(_ text: String?, limit: Int) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
    }

    private static func displayToolName(_ name: String) -> String {
        switch name.split(separator: ".").last.map(String.init) ?? name {
        case "exec", "exec_command", "write_stdin": return "执行命令"
        case "apply_patch": return "编辑文件"
        case "web__run", "web_search": return "网页搜索"
        case "spawn_agent", "followup_task", "wait_agent": return "子任务"
        case "view_image": return "查看图片"
        default: return name
        }
    }
}

private struct CodexScanResult: Sendable {
    var activeTasks: [CodexTaskSnapshot]
    var events: [CodexTaskMonitorEvent]
}

private actor CodexTaskMonitorWorker {
    private struct Tracker {
        var parser: CodexRolloutParser
        var offset: UInt64
        var carry = ""
        var modificationDate: Date
    }

    private let sessionsDirectory: URL
    private var trackers: [String: Tracker] = [:]
    private var dormantOffsets: [String: UInt64] = [:]
    private var bootstrapped = false
    private var scanCount = 0

    init(sessionsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
    }

    func scan() -> CodexScanResult {
        let files = discoverFiles(fullSweep: !bootstrapped || scanCount % 20 == 0)
        scanCount += 1
        var events: [CodexTaskMonitorEvent] = []

        if !bootstrapped {
            for file in files {
                let path = file.url.path
                dormantOffsets[path] = file.size
                if Date().timeIntervalSince(file.modifiedAt) <= 30 * 60 {
                    trackers[path] = makeBackfilledTracker(file)
                }
            }
            bootstrapped = true
        } else {
            for file in files {
                let path = file.url.path
                if trackers[path] == nil {
                    if let offset = dormantOffsets[path] {
                        trackers[path] = makeResumedTracker(file, offset: offset)
                    } else {
                        trackers[path] = Tracker(
                            parser: hydratedParser(for: file.url),
                            offset: 0,
                            modificationDate: file.modifiedAt
                        )
                    }
                }
                events.append(contentsOf: pump(path: path, file: file))
                dormantOffsets[path] = file.size
            }
        }

        let expiry = Date().addingTimeInterval(-60 * 60)
        let active: [CodexTaskSnapshot] = trackers.values.compactMap { tracker -> CodexTaskSnapshot? in
            guard !tracker.parser.isIgnored,
                  tracker.parser.task.phase.isActive,
                  tracker.modificationDate >= expiry else { return nil }
            return tracker.parser.task
        }.sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }

        return CodexScanResult(activeTasks: active, events: events)
    }

    private struct RolloutFile {
        var url: URL
        var size: UInt64
        var modifiedAt: Date
    }

    private func discoverFiles(fullSweep: Bool) -> [RolloutFile] {
        guard FileManager.default.fileExists(atPath: sessionsDirectory.path) else { return [] }
        let roots: [URL]
        if fullSweep {
            roots = [sessionsDirectory]
        } else {
            let calendar = Calendar(identifier: .gregorian)
            roots = (0..<3).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
                return sessionsDirectory
                    .appendingPathComponent(String(format: "%04d", year), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", month), isDirectory: true)
                    .appendingPathComponent(String(format: "%02d", day), isDirectory: true)
            }
        }

        var results: [RolloutFile] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                results.append(RolloutFile(
                    url: url,
                    size: UInt64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ))
            }
        }
        // A Codex Desktop conversation can keep appending to the rollout under
        // its original start date. Keep already-active old sessions hot instead
        // of waiting for the next full directory sweep.
        if !fullSweep {
            let knownPaths = Set(results.map { $0.url.path })
            for path in trackers.keys where !knownPaths.contains(path) {
                let url = URL(fileURLWithPath: path)
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                results.append(RolloutFile(
                    url: url,
                    size: UInt64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ))
            }
        }
        return results
    }

    private func hydratedParser(for url: URL) -> CodexRolloutParser {
        var parser = CodexRolloutParser(fallbackID: url.deletingPathExtension().lastPathComponent)
        if let firstLine = readFirstLine(url: url) {
            parser.consume(line: firstLine)
        }
        return parser
    }

    private func makeBackfilledTracker(_ file: RolloutFile) -> Tracker {
        var parser = hydratedParser(for: file.url)
        let probe = min(file.size, 256 * 1024)
        let start = file.size - probe
        if let data = read(url: file.url, offset: start, length: Int(probe)),
           var text = String(data: data, encoding: .utf8) {
            if start > 0, let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                _ = parser.consume(line: String(line), observedAt: file.modifiedAt)
            }
        }
        return Tracker(parser: parser, offset: file.size, modificationDate: file.modifiedAt)
    }

    private func makeResumedTracker(_ file: RolloutFile, offset: UInt64) -> Tracker {
        Tracker(
            parser: hydratedParser(for: file.url),
            offset: min(offset, file.size),
            modificationDate: file.modifiedAt
        )
    }

    private func pump(path: String, file: RolloutFile) -> [CodexTaskMonitorEvent] {
        guard var tracker = trackers[path] else { return [] }
        if file.size < tracker.offset {
            tracker.offset = 0
            tracker.carry = ""
        }
        guard file.size > tracker.offset else {
            tracker.modificationDate = file.modifiedAt
            trackers[path] = tracker
            return []
        }

        let byteCount = Int(min(file.size - tracker.offset, 512 * 1024))
        guard let data = read(url: file.url, offset: tracker.offset, length: byteCount),
              let chunk = String(data: data, encoding: .utf8) else { return [] }
        tracker.offset += UInt64(data.count)
        tracker.modificationDate = file.modifiedAt

        let joined = tracker.carry + chunk
        var lines = joined.components(separatedBy: "\n")
        tracker.carry = lines.popLast() ?? ""
        var events: [CodexTaskMonitorEvent] = []
        for line in lines where !line.isEmpty {
            if let event = tracker.parser.consume(line: line, observedAt: file.modifiedAt) {
                events.append(event)
            }
        }
        trackers[path] = tracker
        return events
    }

    private func readFirstLine(url: URL) -> String? {
        guard let data = read(url: url, offset: 0, length: 1024 * 1024),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    private func read(url: URL, offset: UInt64, length: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: length)
        } catch {
            return nil
        }
    }
}

@MainActor
final class CodexTaskMonitor: ObservableObject {
    static let shared = CodexTaskMonitor()

    @Published private(set) var activeTasks: [CodexTaskSnapshot] = []
    @Published private(set) var lastEvent: CodexTaskMonitorEvent?

    private let worker: CodexTaskMonitorWorker
    private var monitorTask: Task<Void, Never>?

    init(sessionsDirectory: URL = CodexTaskMonitor.defaultSessionsDirectory()) {
        worker = CodexTaskMonitorWorker(sessionsDirectory: sessionsDirectory)
    }

    nonisolated private static func defaultSessionsDirectory() -> URL {
        if let configuredHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !configuredHome.isEmpty {
            return URL(fileURLWithPath: configuredHome, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self, worker] in
            while !Task.isCancelled {
                let result = await worker.scan()
                guard let self else { return }
                for event in result.events { self.lastEvent = event }
                self.activeTasks = result.activeTasks
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    deinit {
        monitorTask?.cancel()
    }
}

@MainActor
final class GetCodexTaskStatusTool: LegacyAgentTool {
    let definition = AgentToolDefinition(
        name: "get_codex_task_status",
        description: "读取本机 Codex CLI 和 Codex Desktop 当前正在运行、执行工具或等待用户回复的任务。用户询问 Codex 在做什么、进度或是否完成时调用。",
        parameters: ["type": "object", "properties": [:], "additionalProperties": false]
    )
    let requiresConfirmation = false
    private let monitor: CodexTaskMonitor

    init(monitor: CodexTaskMonitor = .shared) {
        self.monitor = monitor
    }

    func approvalSummary(arguments: [String: Any]) -> String { "读取 Codex 任务状态" }

    func execute(
        arguments: [String: Any],
        completion: @escaping @MainActor (AgentToolExecutionResult) -> Void
    ) {
        let tasks = monitor.activeTasks
        guard !tasks.isEmpty else {
            completion(.success("当前没有正在运行的 Codex 任务。"))
            return
        }
        let rows = tasks.map { task -> [String: Any] in
            var row: [String: Any] = [
                "id": task.id,
                "title": task.title,
                "status": task.phase.rawValue,
                "status_text": task.phase.displayName,
                "updated_at": task.updatedAt.ISO8601Format()
            ]
            if let directory = task.workingDirectory { row["working_directory"] = directory }
            if let tool = task.currentTool { row["current_tool"] = tool }
            if let originator = task.originator { row["originator"] = originator }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["running_tasks": rows], options: [.sortedKeys]),
              let output = String(data: data, encoding: .utf8) else {
            completion(.failure("无法序列化 Codex 任务状态"))
            return
        }
        completion(.success(output))
    }
}
