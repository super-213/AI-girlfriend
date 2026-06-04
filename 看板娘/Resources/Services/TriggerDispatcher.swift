//
//  TriggerDispatcher.swift
//  桌面宠物应用
//
//  触发器意图检测与结构化调度
//

import Foundation

enum TriggerHandlingResult: Equatable {
    case noEnabledTriggers
    case notMatched
    case executed(String)
    case failed(String)
}

final class TriggerDispatcher {
    static let shared = TriggerDispatcher()

    private let store: TriggerStore
    private let apiManager: APIManager
    private let player: LocalMP3PlayerService

    init(
        store: TriggerStore = .shared,
        apiManager: APIManager = APIManager(),
        player: LocalMP3PlayerService = .shared
    ) {
        self.store = store
        self.apiManager = apiManager
        self.player = player
    }

    func handleUserInput(_ input: String, completion: @escaping (TriggerHandlingResult) -> Void) {
        let enabledTriggers = store.enabledTriggersForRecognition()
        guard !enabledTriggers.isEmpty else {
            completion(.noEnabledTriggers)
            return
        }

        store.setRecognizing(true)
        apiManager.sendJSONRequest(messages: recognitionMessages(input: input, triggers: enabledTriggers)) { [weak self] output in
            guard let self else { return }
            self.store.setRecognizing(false)

            guard let result = Self.strictRecognitionResult(from: output),
                  result.matched else {
                completion(.notMatched)
                return
            }

            let dispatchResult = self.dispatch(result)
            completion(dispatchResult)
        }
    }

    private func dispatch(_ result: TriggerRecognitionResult) -> TriggerHandlingResult {
        guard let triggerId = result.triggerId,
              let type = result.type,
              let keyword = result.keyword,
              let trigger = store.trigger(id: triggerId),
              trigger.isEnabled else {
            return .notMatched
        }

        let expectedKeyword = type == .start ? trigger.startKeyword : trigger.stopKeyword
        guard keyword == expectedKeyword else {
            return .notMatched
        }

        switch type {
        case .start:
            return start(trigger)
        case .stop:
            return stop(trigger)
        }
    }

    private func start(_ trigger: TriggerDefinition) -> TriggerHandlingResult {
        terminateActiveAudioRunIfNeeded()
        terminateCurrentRun(for: trigger.id)

        let run = store.beginRun(triggerId: trigger.id, type: .start)
        store.updateRun(run.id, triggerId: trigger.id, status: .executing)

        do {
            try player.play(bookmarkData: trigger.action.audioBookmarkData, triggerId: trigger.id) { [weak self] finishedTriggerId in
                DispatchQueue.main.async {
                    guard let self,
                          self.store.runtimeStates[finishedTriggerId]?.currentRunId == run.id else {
                        return
                    }
                    self.store.updateRun(run.id, triggerId: finishedTriggerId, status: .succeeded)
                }
            }
            return .executed("已触发：\(trigger.normalizedTitle)")
        } catch {
            let message = error.localizedDescription
            store.updateRun(run.id, triggerId: trigger.id, status: .failed, errorMessage: message)
            return .failed(message)
        }
    }

    private func stop(_ trigger: TriggerDefinition) -> TriggerHandlingResult {
        let previousRunId = store.runtimeStates[trigger.id]?.currentRunId
        player.stop()

        if let previousRunId {
            store.updateRun(previousRunId, triggerId: trigger.id, status: .terminated)
        }

        let run = store.beginRun(triggerId: trigger.id, type: .stop)
        store.updateRun(run.id, triggerId: trigger.id, status: .terminated)
        return .executed("已终止：\(trigger.normalizedTitle)")
    }

    private func terminateCurrentRun(for triggerId: UUID) {
        guard let currentRunId = store.runtimeStates[triggerId]?.currentRunId else { return }
        store.updateRun(currentRunId, triggerId: triggerId, status: .terminated)
    }

    private func terminateActiveAudioRunIfNeeded() {
        guard let active = store.runtimeStates.values.first(where: { $0.status == .executing }),
              let runId = active.currentRunId else {
            player.stop()
            return
        }

        player.stop()
        store.updateRun(runId, triggerId: active.triggerId, status: .terminated)
    }

    private func recognitionMessages(input: String, triggers: [TriggerDefinition]) -> [[String: String]] {
        [
            ["role": "system", "content": recognitionPrompt(triggers: triggers)],
            ["role": "user", "content": input]
        ]
    }

    private func recognitionPrompt(triggers: [TriggerDefinition]) -> String {
        let triggerDescriptions = triggers.enumerated().map { index, trigger in
            """
            \(index + 1). triggerId: \(trigger.id.uuidString)
            名称: \(trigger.normalizedTitle)
            start 输入描述: \(trigger.inputDescription)
            start keyword: \(trigger.startKeyword)
            stop 输入描述: \(trigger.stopInputDescription)
            stop keyword: \(trigger.stopKeyword)
            """
        }.joined(separator: "\n\n")

        return """
        你是触发器意图检测器，只判断用户输入是否匹配下面的触发器，不要回答用户问题。
        必须只返回一个 JSON 对象，不能包含 Markdown、解释、代码块或多余文本。
        如果匹配 start 或 stop，只返回 {"matched":true,"triggerId":"...","keyword":"...","type":"start"} 或 {"matched":true,"triggerId":"...","keyword":"...","type":"stop"}。
        如果没有任何匹配，只返回 {"matched":false}。
        如果多个触发器可能匹配，必须按列表顺序只选择第一个最佳匹配。
        不能生成文件路径、Shell 命令、系统操作或任何未在列表中出现的 keyword。

        触发器列表：
        \(triggerDescriptions)
        """
    }

    static func strictRecognitionResult(from rawOutput: String) -> TriggerRecognitionResult? {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}", !trimmed.contains("```"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let allowedKeys: Set<String> = ["matched", "triggerId", "keyword", "type"]
        guard Set(object.keys).isSubset(of: allowedKeys),
              let matched = object["matched"] as? Bool else {
            return nil
        }

        guard matched else {
            return object.keys.count == 1 ? TriggerRecognitionResult(matched: false) : nil
        }

        guard let triggerIdText = object["triggerId"] as? String,
              let triggerId = UUID(uuidString: triggerIdText),
              let keyword = object["keyword"] as? String,
              let typeText = object["type"] as? String,
              let type = TriggerMatchType(rawValue: typeText) else {
            return nil
        }

        return TriggerRecognitionResult(
            matched: true,
            triggerId: triggerId,
            keyword: keyword,
            type: type
        )
    }
}
