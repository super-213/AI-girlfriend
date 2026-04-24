//
//  AutomationStore.swift
//  桌面宠物应用
//
//  自动化流程的持久化和状态管理
//

import Foundation
import Combine

final class AutomationStore: ObservableObject {
    static let shared = AutomationStore()

    @Published private(set) var automations: [AutomationFlow] = []

    private let defaults: UserDefaults
    private let calendar: Calendar

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
        load()
    }

    func addAutomation() {
        let now = Date()
        var automation = AutomationFlow.makeDefault(now: now)
        automation.nextRunAt = nextRunDate(for: automation, from: now)
        automations.insert(automation, at: 0)
        save()
    }

    func automation(id: UUID) -> AutomationFlow? {
        automations.first { $0.id == id }
    }

    func updateAutomation(_ automation: AutomationFlow) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }

        var updated = automation
        updated.updatedAt = Date()
        if updated.isEnabled {
            updated.nextRunAt = nextRunDate(for: updated, from: Date())
        } else {
            updated.nextRunAt = nil
        }

        automations[index] = updated
        save()
    }

    func deleteAutomation(_ automation: AutomationFlow) {
        automations.removeAll { $0.id == automation.id }
        save()
    }

    func setEnabled(_ automation: AutomationFlow, enabled: Bool) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index].isEnabled = enabled
        automations[index].updatedAt = Date()
        if enabled, automations[index].frequency == .runOnce {
            automations[index].lastRunAt = nil
        }
        automations[index].nextRunAt = enabled ? nextRunDate(for: automations[index], from: Date()) : nil
        save()
    }

    func markDeferred(_ automation: AutomationFlow, delay: TimeInterval = 60) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index].nextRunAt = Date().addingTimeInterval(delay)
        save()
    }

    func markCompleted(_ automation: AutomationFlow, at date: Date = Date()) {
        guard let index = automations.firstIndex(where: { $0.id == automation.id }) else { return }
        automations[index].lastRunAt = date
        automations[index].updatedAt = date

        if automations[index].frequency == .runOnce {
            automations[index].isEnabled = false
            automations[index].nextRunAt = nil
        } else {
            automations[index].nextRunAt = automations[index].frequency.nextRunDate(after: date, calendar: calendar)
        }

        save()
    }

    func nextEnabledAutomationDate() -> Date? {
        automations
            .filter { $0.isEnabled && !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap(\.nextRunAt)
            .min()
    }

    func dueAutomations(asOf date: Date = Date()) -> [AutomationFlow] {
        automations.filter { automation in
            guard automation.isEnabled,
                  !automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let nextRunAt = automation.nextRunAt else {
                return false
            }
            return nextRunAt <= date
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: AutomationStorageKeys.flows),
              let decoded = try? JSONDecoder().decode([AutomationFlow].self, from: data) else {
            automations = []
            return
        }

        automations = decoded.map { automation in
            guard automation.isEnabled,
                  automation.nextRunAt == nil,
                  !automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return automation
            }

            var repaired = automation
            repaired.nextRunAt = nextRunDate(for: automation, from: Date())
            return repaired
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(automations) else { return }
        defaults.set(data, forKey: AutomationStorageKeys.flows)
    }

    private func nextRunDate(for automation: AutomationFlow, from date: Date) -> Date? {
        guard automation.isEnabled else { return nil }

        if automation.frequency == .runOnce {
            return automation.lastRunAt == nil ? date : nil
        }

        return automation.frequency.nextRunDate(after: date, calendar: calendar)
    }
}
