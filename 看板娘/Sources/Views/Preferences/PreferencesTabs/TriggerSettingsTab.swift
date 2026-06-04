//
//  TriggerSettingsTab.swift
//  桌面宠物应用
//
//  触发器设置页
//

import SwiftUI
import UniformTypeIdentifiers

struct TriggerSettingsTab: View {
    @ObservedObject var store: TriggerStore

    @State private var selectedTriggerID: UUID?
    @State private var draft = TriggerDraft()

    private var selectedTrigger: TriggerDefinition? {
        guard let selectedTriggerID else { return store.triggers.first }
        return store.triggers.first { $0.id == selectedTriggerID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                header

                if store.triggers.isEmpty {
                    emptyState
                } else {
                    triggerList
                    editor
                }
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .onAppear {
            selectIfNeeded()
        }
        .onChange(of: store.triggers) { _, _ in
            selectIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("触发器设置标签")
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text("触发器")
                    .font(DesignFonts.title)
                Text("用模型识别用户输入意图，命中后执行已配置的本地动作。")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }

            Spacer()

            Button(action: addTrigger) {
                Label("添加", systemImage: "plus")
            }
            .enhancedButtonStyle()
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSpacing.lg) {
            Image(systemName: "bolt.badge.clock")
                .font(.system(size: 42))
                .foregroundColor(DesignColors.primary)

            Text("暂无触发器")
                .font(DesignFonts.headline)

            Text("添加后可以配置输入识别、MP3 文件和终止识别。")
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: addTrigger) {
                Label("添加触发器", systemImage: "plus.circle.fill")
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

    private var triggerList: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            HStack {
                Text("触发器列表")
                    .font(DesignFonts.headline)
                Spacer()
                Text("\(store.triggers.filter(\.isEnabled).count) 个启用")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }

            ForEach(store.triggers) { trigger in
                TriggerRow(
                    trigger: trigger,
                    state: runtimeState(for: trigger),
                    isSelected: trigger.id == selectedTrigger?.id,
                    onSelect: {
                        selectedTriggerID = trigger.id
                        draft = TriggerDraft(trigger: trigger)
                    },
                    onToggle: { enabled in
                        store.setEnabled(trigger, enabled: enabled)
                    },
                    onDelete: {
                        store.deleteTrigger(trigger)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let trigger = selectedTrigger {
            let state = runtimeState(for: trigger)

            VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                HStack {
                    Text("编辑触发器")
                        .font(DesignFonts.headline)
                    Spacer()
                    Text(state.status.title)
                        .font(DesignFonts.caption)
                        .foregroundColor(color(for: state.status))
                }

                fieldSection(title: "名称") {
                    TextField("触发器名称", text: $draft.title)
                        .textFieldStyle(.plain)
                        .enhancedTextFieldStyle()
                }

                Toggle("启用触发器", isOn: $draft.isEnabled)
                    .toggleStyle(.switch)

                fieldSection(title: "输入配置") {
                    TextEditor(text: $draft.inputDescription)
                        .font(DesignFonts.input)
                        .frame(minHeight: 90)
                        .padding(DesignSpacing.sm)
                        .scrollContentBackground(.hidden)
                        .background(editorBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    keywordLabel(title: "触发关键词", value: trigger.startKeyword)
                }

                fieldSection(title: "触发配置") {
                    HStack(spacing: DesignSpacing.md) {
                        Image(systemName: "music.note")
                            .foregroundColor(DesignColors.primary)
                        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                            Text("播放音频")
                                .font(DesignFonts.body.weight(.semibold))
                            Text(trigger.action.audioFileName ?? "未选择 MP3 文件")
                                .font(DesignFonts.caption)
                                .foregroundColor(trigger.action.audioFileName == nil ? DesignColors.warning : DesignColors.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            chooseMP3File(for: trigger)
                        } label: {
                            Label("选择", systemImage: "folder")
                        }
                        .enhancedButtonStyle(isPrimary: false)
                    }
                    .padding(DesignSpacing.md)
                    .background(editorBackground)
                }

                fieldSection(title: "终止配置") {
                    TextEditor(text: $draft.stopInputDescription)
                        .font(DesignFonts.input)
                        .frame(minHeight: 76)
                        .padding(DesignSpacing.sm)
                        .scrollContentBackground(.hidden)
                        .background(editorBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    keywordLabel(title: "终止关键词", value: trigger.stopKeyword)
                }

                if let errorMessage = state.lastErrorMessage {
                    Text(errorMessage)
                        .font(DesignFonts.caption)
                        .foregroundColor(DesignColors.error)
                }

                HStack {
                    Button {
                        draft = TriggerDraft(trigger: trigger)
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

    private var editorBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(DesignColors.surfaceLight)
    }

    private func addTrigger() {
        store.addTrigger()
        selectedTriggerID = store.triggers.first?.id
        if let trigger = store.triggers.first {
            draft = TriggerDraft(trigger: trigger)
        }
    }

    private func saveDraft() {
        guard var trigger = selectedTrigger else { return }
        trigger.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        trigger.isEnabled = draft.isEnabled
        trigger.inputDescription = draft.inputDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        trigger.stopInputDescription = draft.stopInputDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateTrigger(trigger)
    }

    private func selectIfNeeded() {
        guard !store.triggers.isEmpty else {
            selectedTriggerID = nil
            draft = TriggerDraft()
            return
        }

        if selectedTrigger == nil {
            selectedTriggerID = store.triggers.first?.id
        }

        if let selectedTrigger {
            draft = TriggerDraft(trigger: selectedTrigger)
        }
    }

    private func runtimeState(for trigger: TriggerDefinition) -> TriggerRuntimeState {
        store.runtimeStates[trigger.id] ?? .idle(triggerId: trigger.id, isEnabled: trigger.isEnabled)
    }

    private func chooseMP3File(for trigger: TriggerDefinition) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mp3") ?? .audio]
        panel.message = "选择要由触发器播放的 MP3 文件"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try store.updateAudioFile(for: trigger, url: url)
            } catch {
                let failed = trigger
                store.updateTrigger(failed)
                let run = store.beginRun(triggerId: failed.id, type: .start)
                store.updateRun(run.id, triggerId: failed.id, status: .failed, errorMessage: error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private func fieldSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text(title)
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)
            content()
        }
    }

    private func keywordLabel(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DesignColors.primary)
                .textSelection(.enabled)
        }
        .padding(DesignSpacing.md)
        .background(editorBackground)
    }

    private func color(for status: TriggerRuntimeStatus) -> Color {
        switch status {
        case .disabled, .idle, .recognizing, .triggered:
            return DesignColors.textSecondary
        case .executing:
            return DesignColors.info
        case .succeeded:
            return DesignColors.success
        case .failed:
            return DesignColors.error
        case .terminated:
            return DesignColors.warning
        }
    }
}

private struct TriggerRow: View {
    let trigger: TriggerDefinition
    let state: TriggerRuntimeState
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignSpacing.md) {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    HStack(spacing: DesignSpacing.sm) {
                        Text(trigger.normalizedTitle)
                            .font(DesignFonts.body.weight(.semibold))
                            .lineLimit(1)

                        Text(trigger.action.type.title)
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
                    get: { trigger.isEnabled },
                    set: onToggle
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(trigger.isEnabled ? "停用触发器" : "启用触发器")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("删除触发器")
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
        if !trigger.isEnabled {
            return "已停用"
        }

        if trigger.inputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请输入识别描述"
        }

        if !trigger.hasRunnableAction {
            return "请选择 MP3 文件"
        }

        return state.status.title
    }
}

private struct TriggerDraft {
    var title: String = ""
    var isEnabled: Bool = true
    var inputDescription: String = ""
    var stopInputDescription: String = ""

    init() {}

    init(trigger: TriggerDefinition) {
        title = trigger.title
        isEnabled = trigger.isEnabled
        inputDescription = trigger.inputDescription
        stopInputDescription = trigger.stopInputDescription
    }

    var canSave: Bool {
        !inputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !stopInputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
