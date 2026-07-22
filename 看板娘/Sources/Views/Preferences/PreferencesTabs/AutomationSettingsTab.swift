//
//  AutomationSettingsTab.swift
//  桌面宠物应用
//
//  自动化流程设置页
//

import SwiftUI

struct AutomationSettingsTab: View {
    @ObservedObject var store: AutomationStore
    @ObservedObject var triggerStore: TriggerStore

    @State private var selectedAutomationID: UUID?
    @State private var draft = AutomationDraft()

    private var selectedAutomation: AutomationFlow? {
        guard let selectedAutomationID else { return store.automations.first }
        return store.automations.first { $0.id == selectedAutomationID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                header

                if store.automations.isEmpty {
                    emptyState
                } else {
                    automationList
                    editor
                }
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .onAppear {
            selectIfNeeded()
        }
        .onChange(of: store.automations) { _, _ in
            selectIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("自动化设置标签")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text("自动化")
                    .font(DesignFonts.title)
                Text("把常用提示词按设定频率自动发送给模型，并显示在宠物输出框。")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }

            Spacer()

            Button(action: addAutomation) {
                Label("添加", systemImage: "plus")
            }
            .enhancedButtonStyle()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSpacing.lg) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 42))
                .foregroundColor(DesignColors.primary)

            Text("暂无自动化流程")
                .font(DesignFonts.headline)

            Text("添加后可以设置提示词、频率，并用开关快速启用或停用。")
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: addAutomation) {
                Label("添加自动化", systemImage: "plus.circle.fill")
            }
            .enhancedButtonStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, DesignSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DesignColors.surfaceLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DesignColors.border.opacity(0.7), lineWidth: 1)
        )
    }

    private var automationList: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack {
                Text("流程列表")
                    .font(DesignFonts.headline)
                Spacer()
                Text("\(store.automations.filter(\.isEnabled).count) 个启用")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }

            ForEach(store.automations) { automation in
                AutomationRow(
                    automation: automation,
                    triggerTitle: triggerTitle(for: automation.triggerId),
                    isSelected: automation.id == selectedAutomation?.id,
                    onSelect: {
                        selectedAutomationID = automation.id
                        draft = AutomationDraft(automation: automation)
                    },
                    onToggle: { enabled in
                        store.setEnabled(automation, enabled: enabled)
                    },
                    onDelete: {
                        store.deleteAutomation(automation)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let automation = selectedAutomation {
            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                HStack {
                    Text("编辑流程")
                        .font(DesignFonts.headline)
                    Spacer()
                    Text(automation.isEnabled ? "启用中" : "已停用")
                        .font(DesignFonts.caption)
                        .foregroundColor(automation.isEnabled ? DesignColors.success : DesignColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("名称")
                        .font(DesignFonts.caption)
                        .foregroundColor(DesignColors.textSecondary)
                    TextField("自动化名称", text: $draft.title)
                        .textFieldStyle(.plain)
                        .enhancedTextFieldStyle()
                }

                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    Text("运行内容")
                        .font(DesignFonts.caption)
                        .foregroundColor(DesignColors.textSecondary)

                    Picker("运行内容", selection: $draft.runMode) {
                        Text("发送提示词").tag(AutomationRunMode.prompt)
                        Text("运行触发器").tag(AutomationRunMode.trigger)
                    }
                    .pickerStyle(.segmented)

                    if draft.runMode == .prompt {
                        TextEditor(text: $draft.prompt)
                            .font(DesignFonts.input)
                            .frame(minHeight: 96)
                            .padding(DesignSpacing.sm)
                            .scrollContentBackground(.hidden)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(DesignColors.surfaceLight)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(DesignColors.border.opacity(0.7), lineWidth: 1)
                            )
                    } else {
                        if runnableTriggers.isEmpty {
                            Text("暂无已启用且配置完整的触发器")
                                .font(DesignFonts.caption)
                                .foregroundColor(DesignColors.warning)
                                .padding(DesignSpacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(DesignColors.surfaceLight)
                                )
                        } else {
                            Picker("触发器", selection: $draft.triggerIDString) {
                                Text("选择触发器").tag("")
                                ForEach(runnableTriggers) { trigger in
                                    Text(trigger.normalizedTitle).tag(trigger.id.uuidString)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(DesignSpacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(DesignColors.surfaceLight)
                            )
                        }
                    }
                }

                FrequencyEditor(
                    kind: $draft.frequencyKind,
                    dayInterval: $draft.dayInterval,
                    scheduledAt: $draft.scheduledAt
                )

                HStack {
                    Button {
                        draft = AutomationDraft(automation: automation)
                    } label: {
                        Label("还原", systemImage: "arrow.counterclockwise")
                    }
                    .enhancedButtonStyle(isPrimary: false)

                    Spacer()

                    Button(action: saveDraft) {
                        Label("保存", systemImage: "checkmark")
                    }
                    .enhancedButtonStyle(isPrimary: true, isDisabled: !draft.canSave)
                    .disabled(!draft.canSave)
                }
            }
            .padding(DesignSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(DesignColors.surfaceMedium)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DesignColors.border.opacity(0.7), lineWidth: 1)
            )
        }
    }

    private func addAutomation() {
        store.addAutomation()
        selectedAutomationID = store.automations.first?.id
        if let automation = store.automations.first {
            draft = AutomationDraft(automation: automation)
        }
    }

    private func saveDraft() {
        guard var automation = selectedAutomation else { return }
        automation.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        automation.prompt = draft.runMode == .prompt ? draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        automation.triggerId = draft.runMode == .trigger ? UUID(uuidString: draft.triggerIDString) : nil
        automation.frequency = AutomationFrequency.from(kind: draft.frequencyKind, dayInterval: draft.dayInterval)
        automation.scheduledAt = draft.scheduledAt
        store.updateAutomation(automation)
    }

    private func selectIfNeeded() {
        guard !store.automations.isEmpty else {
            selectedAutomationID = nil
            draft = AutomationDraft()
            return
        }

        if selectedAutomation == nil {
            selectedAutomationID = store.automations.first?.id
        }

        if let selectedAutomation {
            draft = AutomationDraft(automation: selectedAutomation)
        }
    }

    private var runnableTriggers: [TriggerDefinition] {
        triggerStore.triggers.filter { $0.isEnabled && $0.hasRunnableAction }
    }

    private func triggerTitle(for triggerId: UUID?) -> String? {
        guard let triggerId else { return nil }
        return triggerStore.trigger(id: triggerId)?.normalizedTitle
    }
}

private struct AutomationRow: View {
    let automation: AutomationFlow
    let triggerTitle: String?
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: @MainActor @Sendable (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSpacing.md) {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    HStack(spacing: DesignSpacing.sm) {
                        Text(automation.normalizedTitle)
                            .font(DesignFonts.body.weight(.semibold))
                            .lineLimit(1)

                        Text(automation.frequency.title)
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.primary)
                            .padding(.horizontal, DesignSpacing.sm)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DesignColors.primary.opacity(0.12))
                            )
                    }

                    Text(statusText)
                        .font(DesignFonts.caption)
                        .foregroundColor(DesignColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { automation.isEnabled },
                    set: { enabled in
                        Task { @MainActor in
                            onToggle(enabled)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(automation.isEnabled ? "停用自动化" : "启用自动化")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("删除自动化")
            }
            .padding(DesignSpacing.lg)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isSelected ? DesignColors.primary.opacity(0.12) : DesignColors.surfaceLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? DesignColors.primary.opacity(0.45) : DesignColors.border.opacity(0.6), lineWidth: 1)
        )
    }

    private var statusText: String {
        if !automation.isEnabled {
            return "已停用"
        }

        if automation.triggerId != nil, triggerTitle == nil {
            return "请选择已启用触发器"
        }

        if let triggerTitle {
            if let nextRunAt = automation.nextRunAt {
                return "运行触发器：\(triggerTitle) · \(nextRunAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "运行触发器：\(triggerTitle)"
        }

        if automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请输入提示词后开始运行"
        }

        if let nextRunAt = automation.nextRunAt {
            return "下次运行：\(nextRunAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "等待调度"
    }
}

private struct FrequencyEditor: View {
    @Binding var kind: AutomationFrequency.Kind
    @Binding var dayInterval: Int
    @Binding var scheduledAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("频率")
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)

            Picker("频率", selection: $kind) {
                ForEach(AutomationFrequency.Kind.allCases) { option in
                    Text(title(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)

            DatePicker("计划时间", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .padding(DesignSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DesignColors.surfaceLight)
                )

            if kind == .everyNDays {
                Stepper(value: $dayInterval, in: 2...7) {
                    HStack {
                        Text("每 \(dayInterval) 天")
                        Spacer()
                        Text("2-7")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }
                .padding(DesignSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DesignColors.surfaceLight)
                )
            }
        }
    }

    private func title(for kind: AutomationFrequency.Kind) -> String {
        switch kind {
        case .runOnce: return "仅运行一次"
        case .every15Minutes: return "每15分钟"
        case .hourly: return "每小时"
        case .daily: return "每天"
        case .everyNDays: return "每N天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

private enum AutomationRunMode: String, CaseIterable, Identifiable {
    case prompt
    case trigger

    var id: String { rawValue }
}

private struct AutomationDraft {
    var title: String = ""
    var prompt: String = ""
    var runMode: AutomationRunMode = .prompt
    var triggerIDString: String = ""
    var frequencyKind: AutomationFrequency.Kind = .daily
    var dayInterval: Int = 2
    var scheduledAt: Date = Date()

    init() {}

    init(automation: AutomationFlow) {
        title = automation.title
        prompt = automation.prompt
        if let triggerId = automation.triggerId {
            runMode = .trigger
            triggerIDString = triggerId.uuidString
        } else {
            runMode = .prompt
            triggerIDString = ""
        }
        frequencyKind = automation.frequency.kind
        scheduledAt = automation.scheduledAt
        if case let .everyNDays(interval) = automation.frequency {
            dayInterval = AutomationFrequency.clampedDayInterval(interval)
        }
    }

    var canSave: Bool {
        switch runMode {
        case .prompt:
            return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .trigger:
            return UUID(uuidString: triggerIDString) != nil
        }
    }
}
