//
//  TriggerStore.swift
//  桌面宠物应用
//
//  触发器配置持久化与运行状态管理
//

import Foundation

@MainActor
final class TriggerStore: ObservableObject {
    static let shared = TriggerStore()

    @Published private(set) var triggers: [TriggerDefinition] = []
    @Published private(set) var runtimeStates: [UUID: TriggerRuntimeState] = [:]
    @Published private(set) var runs: [TriggerRun] = []

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addTrigger() {
        let trigger = TriggerDefinition.makeDefault()
        triggers.insert(trigger, at: 0)
        runtimeStates[trigger.id] = .idle(triggerId: trigger.id, isEnabled: trigger.isEnabled)
        save()
    }

    func trigger(id: UUID) -> TriggerDefinition? {
        triggers.first { $0.id == id }
    }

    func updateTrigger(_ trigger: TriggerDefinition) {
        guard let index = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        var updated = trigger
        updated.updatedAt = Date()
        triggers[index] = updated

        if var state = runtimeStates[updated.id] {
            if !updated.isEnabled {
                state.status = .disabled
            } else if state.status == .disabled {
                state.status = .idle
            }
            runtimeStates[updated.id] = state
        } else {
            runtimeStates[updated.id] = .idle(triggerId: updated.id, isEnabled: updated.isEnabled)
        }

        save()
    }

    func deleteTrigger(_ trigger: TriggerDefinition) {
        triggers.removeAll { $0.id == trigger.id }
        runtimeStates.removeValue(forKey: trigger.id)
        runs.removeAll { $0.triggerId == trigger.id }
        save()
    }

    func setEnabled(_ trigger: TriggerDefinition, enabled: Bool) {
        guard let index = triggers.firstIndex(where: { $0.id == trigger.id }) else { return }
        triggers[index].isEnabled = enabled
        triggers[index].updatedAt = Date()

        if var state = runtimeStates[trigger.id] {
            state.status = enabled ? .idle : .disabled
            state.lastErrorMessage = nil
            runtimeStates[trigger.id] = state
        } else {
            runtimeStates[trigger.id] = .idle(triggerId: trigger.id, isEnabled: enabled)
        }

        save()
    }

    func updateAudioFile(for trigger: TriggerDefinition, url: URL) throws {
        guard var updated = self.trigger(id: trigger.id) else { return }
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        updated.action.audioBookmarkData = bookmarkData
        updated.action.audioFileName = url.lastPathComponent
        updated.action.audioFilePath = url.path
        updateTrigger(updated)
    }

    func enabledTriggersForRecognition() -> [TriggerDefinition] {
        triggers.filter { trigger in
            trigger.isEnabled
                && !trigger.inputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && trigger.hasRunnableAction
        }
    }

    func setRecognizing(_ isRecognizing: Bool) {
        for trigger in triggers where trigger.isEnabled {
            var state = runtimeStates[trigger.id] ?? .idle(triggerId: trigger.id, isEnabled: true)
            if isRecognizing {
                state.status = .recognizing
            } else if state.status == .recognizing {
                state.status = .idle
            }
            runtimeStates[trigger.id] = state
        }
    }

    @discardableResult
    func beginRun(triggerId: UUID, type: TriggerMatchType) -> TriggerRun {
        let run = TriggerRun(
            id: UUID(),
            triggerId: triggerId,
            type: type,
            startedAt: Date(),
            endedAt: nil,
            status: type == .start ? .triggered : .terminated,
            errorMessage: nil
        )
        runs.insert(run, at: 0)
        runtimeStates[triggerId] = TriggerRuntimeState(
            triggerId: triggerId,
            status: run.status,
            currentRunId: run.id,
            startedAt: run.startedAt,
            endedAt: nil,
            lastErrorMessage: nil
        )
        return run
    }

    func updateRun(_ runId: UUID, triggerId: UUID, status: TriggerRuntimeStatus, errorMessage: String? = nil) {
        if let index = runs.firstIndex(where: { $0.id == runId }) {
            runs[index].status = status
            runs[index].errorMessage = errorMessage
            if status == .succeeded || status == .failed || status == .terminated {
                runs[index].endedAt = Date()
            }
        }

        var state = runtimeStates[triggerId] ?? .idle(triggerId: triggerId, isEnabled: true)
        state.status = status
        state.currentRunId = runId
        state.lastErrorMessage = errorMessage
        if state.startedAt == nil {
            state.startedAt = Date()
        }
        if status == .succeeded || status == .failed || status == .terminated {
            state.endedAt = Date()
        }
        runtimeStates[triggerId] = state
    }

    private func load() {
        guard let data = defaults.data(forKey: TriggerStorageKeys.definitions),
              let decoded = try? JSONDecoder().decode([TriggerDefinition].self, from: data) else {
            triggers = []
            runtimeStates = [:]
            return
        }

        triggers = decoded
        runtimeStates = Dictionary(
            uniqueKeysWithValues: decoded.map {
                ($0.id, TriggerRuntimeState.idle(triggerId: $0.id, isEnabled: $0.isEnabled))
            }
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(triggers) else { return }
        defaults.set(data, forKey: TriggerStorageKeys.definitions)
    }
}
