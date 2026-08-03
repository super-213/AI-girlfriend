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

    @State private var editorPresentation: TriggerEditorPresentation?
    @State private var triggerPendingDeletion: TriggerDefinition?
    @State private var isShowingDeleteConfirmation = false
    @State private var saveFeedback: TriggerSaveFeedback?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, LayoutConstants.horizontalPadding)
                .padding(.top, LayoutConstants.horizontalPadding)
                .padding(.bottom, DesignSpacing.xl)

            if store.triggers.isEmpty {
                emptyState
                    .padding(.horizontal, LayoutConstants.horizontalPadding)
                    .padding(.bottom, LayoutConstants.horizontalPadding)
            } else {
                triggerList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if let saveFeedback {
                TriggerSaveFeedbackView(message: saveFeedback.message)
                    .padding(.bottom, DesignSpacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $editorPresentation) { presentation in
            TriggerEditorSheet(
                store: store,
                originalTrigger: presentation.trigger,
                isNew: presentation.isNew,
                onSaved: { trigger in
                    editorPresentation = nil
                    showSaveFeedback(
                        presentation.isNew
                            ? "已添加“\(trigger.normalizedTitle)”"
                            : "已保存“\(trigger.normalizedTitle)”"
                    )
                }
            )
        }
        .alert(
            "删除触发器？",
            isPresented: $isShowingDeleteConfirmation,
            presenting: triggerPendingDeletion
        ) { trigger in
            Button("删除", role: .destructive) {
                store.deleteTrigger(trigger)
                triggerPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                triggerPendingDeletion = nil
            }
        } message: { trigger in
            Text("“\(trigger.normalizedTitle)”及其运行记录将被删除，此操作无法撤销。")
        }
        .task(id: saveFeedback?.id) {
            guard saveFeedback != nil else { return }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(DesignAnimation.gentle) {
                saveFeedback = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("触发器设置标签")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSpacing.xl) {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text("触发器")
                    .font(DesignFonts.title)
                Text("用模型识别用户输入意图，命中后执行已配置的本地动作。")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }

            Spacer()

            Button(action: presentNewTrigger) {
                Label("添加", systemImage: "plus")
            }
            .enhancedButtonStyle()
            .keyboardShortcut("n", modifiers: .command)
            .help("添加触发器（⌘N）")
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

            Button(action: presentNewTrigger) {
                Label("添加触发器", systemImage: "plus.circle.fill")
            }
            .enhancedButtonStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DesignSpacing.sm) {
                Text("触发器列表")
                    .font(DesignFonts.headline)

                Text("\(store.triggers.count)")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(DesignColors.textSecondary)
                    .padding(.horizontal, DesignSpacing.sm)
                    .padding(.vertical, 2)
                    .background(DesignColors.surfaceMedium, in: Capsule())

                Spacer()

                Label("\(store.triggers.filter(\.isEnabled).count) 个启用", systemImage: "checkmark.circle.fill")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }
            .padding(.horizontal, LayoutConstants.horizontalPadding)
            .padding(.bottom, DesignSpacing.md)

            ScrollView {
                LazyVStack(spacing: DesignSpacing.md) {
                    ForEach(store.triggers) { trigger in
                        TriggerRow(
                            store: store,
                            trigger: trigger,
                            state: runtimeState(for: trigger),
                            onEdit: { presentEditor(for: trigger) },
                            onDelete: { requestDeletion(of: trigger) }
                        )
                    }
                }
                .padding(.horizontal, LayoutConstants.horizontalPadding)
                .padding(.bottom, LayoutConstants.horizontalPadding + 56)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func runtimeState(for trigger: TriggerDefinition) -> TriggerRuntimeState {
        store.runtimeStates[trigger.id] ?? .idle(triggerId: trigger.id, isEnabled: trigger.isEnabled)
    }

    private func presentNewTrigger() {
        editorPresentation = TriggerEditorPresentation(
            trigger: .makeDefault(),
            isNew: true
        )
    }

    private func presentEditor(for trigger: TriggerDefinition) {
        editorPresentation = TriggerEditorPresentation(trigger: trigger, isNew: false)
    }

    private func requestDeletion(of trigger: TriggerDefinition) {
        triggerPendingDeletion = trigger
        isShowingDeleteConfirmation = true
    }

    private func showSaveFeedback(_ message: String) {
        withAnimation(DesignAnimation.gentle) {
            saveFeedback = TriggerSaveFeedback(message: message)
        }
    }
}

private struct TriggerEditorPresentation: Identifiable {
    let trigger: TriggerDefinition
    let isNew: Bool

    var id: UUID { trigger.id }
}

private struct TriggerSaveFeedback: Identifiable {
    let id = UUID()
    let message: String
}

private struct TriggerSaveFeedbackView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(DesignFonts.body.weight(.medium))
            .foregroundColor(DesignColors.textPrimary)
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.vertical, DesignSpacing.md)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(DesignColors.success.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
            .accessibilityAddTraits(.isStaticText)
    }
}

private struct TriggerRow: View {
    @ObservedObject var store: TriggerStore

    let trigger: TriggerDefinition
    let state: TriggerRuntimeState
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            statusIndicator

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
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignSpacing.lg)

            Toggle("", isOn: Binding(
                get: { trigger.isEnabled },
                set: { enabled in
                    store.setEnabled(trigger, enabled: enabled)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .help(trigger.isEnabled ? "停用触发器" : "启用触发器")
            .accessibilityLabel(trigger.isEnabled ? "停用\(trigger.normalizedTitle)" : "启用\(trigger.normalizedTitle)")

            Button(action: onEdit) {
                Label("编辑", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("编辑\(trigger.normalizedTitle)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(DesignColors.error)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("删除\(trigger.normalizedTitle)")
            .accessibilityLabel("删除\(trigger.normalizedTitle)")
        }
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isHovered ? DesignColors.surfaceMedium : DesignColors.surfaceLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignColors.border.opacity(isHovered ? 0.9 : 0.55), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(DesignAnimation.gentle, value: isHovered)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.2), lineWidth: 5)
            )
            .padding(.horizontal, 3)
            .accessibilityHidden(true)
    }

    private var statusText: String {
        if !trigger.isEnabled {
            return "已停用"
        }

        if trigger.inputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "需要补充识别描述"
        }

        if !trigger.hasRunnableAction {
            return "需要选择 MP3 文件"
        }

        return state.status.title
    }

    private var statusColor: Color {
        if !trigger.isEnabled {
            return DesignColors.textSecondary
        }

        if trigger.inputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !trigger.hasRunnableAction {
            return DesignColors.warning
        }

        return color(for: state.status)
    }
}

private struct TriggerEditorSheet: View {
    @ObservedObject var store: TriggerStore

    let originalTrigger: TriggerDefinition
    let isNew: Bool
    let onSaved: (TriggerDefinition) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TriggerDraft
    @State private var fileErrorMessage = ""
    @State private var isShowingFileError = false

    init(
        store: TriggerStore,
        originalTrigger: TriggerDefinition,
        isNew: Bool,
        onSaved: @escaping (TriggerDefinition) -> Void
    ) {
        self.store = store
        self.originalTrigger = originalTrigger
        self.isNew = isNew
        self.onSaved = onSaved
        _draft = State(initialValue: TriggerDraft(trigger: originalTrigger))
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSpacing.lg) {
                    formSection(title: "基本信息", systemImage: "text.cursor") {
                        fieldLabel("名称")
                        TextField("触发器名称", text: $draft.title)
                            .textFieldStyle(.plain)
                            .enhancedTextFieldStyle()

                        Toggle("启用此触发器", isOn: $draft.isEnabled)
                            .toggleStyle(.switch)
                    }

                    formSection(title: "识别用户意图", systemImage: "text.bubble") {
                        fieldLabel("描述用户在什么情况下想触发动作")
                        textEditor(text: $draft.inputDescription, minHeight: 88)
                        keywordLabel(title: "触发关键词", value: originalTrigger.startKeyword)
                    }

                    formSection(title: "执行动作", systemImage: "music.note") {
                        HStack(spacing: DesignSpacing.md) {
                            Image(systemName: draft.audioFileName == nil ? "waveform.badge.exclamationmark" : "waveform")
                                .font(.title3)
                                .foregroundColor(draft.audioFileName == nil ? DesignColors.warning : DesignColors.primary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                                Text("播放音频")
                                    .font(DesignFonts.body.weight(.semibold))
                                Text(draft.audioFileName ?? "尚未选择 MP3 文件")
                                    .font(DesignFonts.caption)
                                    .foregroundColor(draft.audioFileName == nil ? DesignColors.warning : DesignColors.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer()

                            Button {
                                chooseMP3File()
                            } label: {
                                Label(draft.audioFileName == nil ? "选择" : "更换", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    formSection(title: "终止动作", systemImage: "stop.circle") {
                        fieldLabel("描述用户在什么情况下想停止当前动作")
                        textEditor(text: $draft.stopInputDescription, minHeight: 76)
                        keywordLabel(title: "终止关键词", value: originalTrigger.stopKeyword)
                    }

                    if let errorMessage = runtimeState.lastErrorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.error)
                            .padding(DesignSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DesignColors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(DesignSpacing.xl)
            }
            .scrollIndicators(.automatic)

            actionBar
        }
        .frame(width: 620)
        .frame(minHeight: 560, idealHeight: 650)
        .alert("无法使用所选文件", isPresented: $isShowingFileError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(fileErrorMessage)
        }
    }

    private var sheetHeader: some View {
        HStack(alignment: .center, spacing: DesignSpacing.lg) {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(isNew ? "添加触发器" : "编辑触发器")
                    .font(DesignFonts.headline)
                Text(isNew ? "完成必要配置后添加到列表" : originalTrigger.normalizedTitle)
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Label(
                draft.isEnabled ? "将启用" : "将停用",
                systemImage: draft.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
            )
            .font(DesignFonts.caption)
            .foregroundColor(draft.isEnabled ? DesignColors.success : DesignColors.textSecondary)
        }
        .padding(DesignSpacing.xl)
    }

    private var actionBar: some View {
        HStack(spacing: DesignSpacing.md) {
            if !draft.canSave {
                Label("请填写触发与终止描述", systemImage: "exclamationmark.circle")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.warning)
            } else if hasUnsavedChanges || isNew {
                Label("有未保存的更改", systemImage: "circle.fill")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(DesignColors.warning, DesignColors.textSecondary)
            } else {
                Text("没有未保存的更改")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }

            Spacer()

            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                saveDraft()
            } label: {
                Label(isNew ? "添加" : "保存", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isSaveDisabled)
        }
        .padding(.horizontal, DesignSpacing.xl)
        .padding(.vertical, DesignSpacing.lg)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var runtimeState: TriggerRuntimeState {
        store.runtimeStates[originalTrigger.id]
            ?? .idle(triggerId: originalTrigger.id, isEnabled: originalTrigger.isEnabled)
    }

    private var hasUnsavedChanges: Bool {
        draft != TriggerDraft(trigger: originalTrigger)
    }

    private var isSaveDisabled: Bool {
        !draft.canSave || (!isNew && !hasUnsavedChanges)
    }

    @ViewBuilder
    private func formSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Label(title, systemImage: systemImage)
                .font(DesignFonts.body.weight(.semibold))
                .foregroundColor(DesignColors.textPrimary)

            content()
        }
        .padding(DesignSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.surfaceLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignColors.border.opacity(0.6), lineWidth: 1)
        )
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(DesignFonts.caption)
            .foregroundColor(DesignColors.textSecondary)
    }

    private func textEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(DesignFonts.input)
            .frame(minHeight: minHeight)
            .padding(DesignSpacing.sm)
            .scrollContentBackground(.hidden)
            .background(DesignColors.surfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignColors.border.opacity(0.55), lineWidth: 1)
            )
    }

    private func keywordLabel(title: String, value: String) -> some View {
        HStack(spacing: DesignSpacing.md) {
            Text(title)
                .font(DesignFonts.caption)
                .foregroundColor(DesignColors.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DesignColors.primary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
        .padding(DesignSpacing.md)
        .background(DesignColors.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chooseMP3File() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mp3") ?? .audio]
        panel.message = "选择要由触发器播放的 MP3 文件"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                draft.audioBookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                draft.audioFileName = url.lastPathComponent
                draft.audioFilePath = url.path
            } catch {
                fileErrorMessage = error.localizedDescription
                isShowingFileError = true
            }
        }
    }

    private func saveDraft() {
        let updated = draft.applying(to: originalTrigger)

        if isNew {
            store.addTrigger(updated)
        } else {
            store.updateTrigger(updated)
        }

        onSaved(updated)
        dismiss()
    }
}

private struct TriggerDraft: Equatable {
    var title: String
    var isEnabled: Bool
    var inputDescription: String
    var stopInputDescription: String
    var audioBookmarkData: Data?
    var audioFileName: String?
    var audioFilePath: String?

    init(trigger: TriggerDefinition) {
        title = trigger.title
        isEnabled = trigger.isEnabled
        inputDescription = trigger.inputDescription
        stopInputDescription = trigger.stopInputDescription
        audioBookmarkData = trigger.action.audioBookmarkData
        audioFileName = trigger.action.audioFileName
        audioFilePath = trigger.action.audioFilePath
    }

    var canSave: Bool {
        !inputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !stopInputDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applying(to trigger: TriggerDefinition) -> TriggerDefinition {
        var updated = trigger
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.isEnabled = isEnabled
        updated.inputDescription = inputDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.stopInputDescription = stopInputDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.action.audioBookmarkData = audioBookmarkData
        updated.action.audioFileName = audioFileName
        updated.action.audioFilePath = audioFilePath
        return updated
    }
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
