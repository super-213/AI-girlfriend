//
//  SkillsSettingsTab.swift
//  看板娘
//
//  Agent 和 Skill Markdown 文件工作台
//

import AppKit
import SwiftUI

struct SkillsSettingsTab: View {
    let agentFile: AgentFile?
    let skillFiles: [SkillFile]
    let onImportAgent: () -> Void
    let onGenerateAgent: () -> AgentFile?
    let onRemoveAgent: () -> Bool
    let onImportSkills: () -> Void
    let onDeleteSkill: (Int) -> Bool
    let onReadFile: (String) -> String?
    let onSaveAgent: (String) -> Bool
    let onSaveSkill: (UUID, String) -> Bool
    let onCreateSkill: (String) -> SkillFile?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var selection: SkillDocument.ID?
    @State private var draftContent = ""
    @State private var savedContent = ""
    @State private var pendingSelection: SkillDocument.ID?
    @State private var pendingDeletion: SkillDocument.ID?
    @State private var isShowingUnsavedAlert = false
    @State private var isShowingCreateSheet = false
    @State private var isShowingGenerateConfirmation = false
    @State private var editorMode: EditorMode = .source

    var body: some View {
        HStack(spacing: 0) {
            documentLibrary
                .frame(minWidth: 210, idealWidth: 228, maxWidth: 250)

            Divider()

            editorArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("技能文件工作台")
        .onAppear(perform: reconcileSelection)
        .onChange(of: documentIDs) { _, _ in
            reconcileSelection()
        }
        .onChange(of: agentFile?.updatedAt) { _, _ in
            guard selection == .agent, !hasUnsavedChanges,
                  let document = selectedDocument else { return }
            load(document)
        }
        .alert("保存当前修改？", isPresented: $isShowingUnsavedAlert) {
            Button("保存并继续") {
                guard saveCurrentDocument() else { return }
                continuePendingSelection()
            }
            Button("放弃修改", role: .destructive) {
                continuePendingSelection()
            }
            Button("取消", role: .cancel) {
                pendingSelection = nil
            }
        } message: {
            Text("“\(selectedDocument?.name ?? "当前文件")”包含尚未保存的内容。")
        }
        .confirmationDialog(
            "删除“\(document(for: pendingDeletion)?.name ?? "文件")”？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除文件", role: .destructive, action: deletePendingDocument)
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("文件会从应用的技能目录中永久删除，此操作无法撤销。")
        }
        .confirmationDialog(
            agentFile == nil ? "生成 agent.md 示例？" : "用示例覆盖 agent.md？",
            isPresented: $isShowingGenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button(agentFile == nil ? "生成示例" : "覆盖并生成", role: agentFile == nil ? nil : .destructive) {
                generateAgentTemplate()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(agentFile == nil
                 ? "将创建一份可直接编辑的代理指令模板。"
                 : "现有 agent.md 内容会被替换，且无法撤销。")
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            NewSkillFileSheet { name in
                guard let skill = onCreateSkill(name) else { return false }
                isShowingCreateSheet = false
                let document = SkillDocument(
                    id: .skill(skill.id),
                    name: skill.name,
                    path: skill.path,
                    kind: .skill,
                    fallbackDate: skill.addedAt
                )
                selection = document.id
                load(document)
                return true
            }
        }
    }

    // MARK: - Library

    private var documentLibrary: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("技能文件")
                        .font(.headline)
                    Text("\(documents.count) 个 Markdown 文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                addMenu
            }
            .padding(.horizontal, DesignSpacing.lg)
            .padding(.top, DesignSpacing.lg)
            .padding(.bottom, DesignSpacing.md)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    librarySectionTitle("代理规则")

                    if let agentDocument {
                        documentRow(agentDocument)
                    } else {
                        missingAgentRow
                    }

                    librarySectionTitle("扩展技能")
                        .padding(.top, DesignSpacing.sm)

                    if skillDocuments.isEmpty {
                        emptySkillsRow
                    } else {
                        ForEach(skillDocuments) { document in
                            documentRow(document)
                        }
                    }
                }
                .padding(.horizontal, DesignSpacing.sm)
                .padding(.bottom, DesignSpacing.md)
            }

            Divider()

            HStack(spacing: DesignSpacing.sm) {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Label("新建", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .help("新建一个可直接编辑的 skill.md")

                Button(action: onImportSkills) {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .help("导入一个或多个 Markdown 技能文件")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(DesignSpacing.md)
        }
        .background {
            if reduceTransparency {
                Color(nsColor: .controlBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("新建 skill.md", systemImage: "doc.badge.plus") {
                isShowingCreateSheet = true
            }
            Button("导入 skill.md…", systemImage: "square.and.arrow.down") {
                onImportSkills()
            }

            Divider()

            Button(agentFile == nil ? "导入 agent.md…" : "替换 agent.md…", systemImage: "doc.badge.arrow.up") {
                onImportAgent()
            }
            .disabled(hasUnsavedChanges)

            Button("生成 agent.md 示例", systemImage: "wand.and.stars") {
                isShowingGenerateConfirmation = true
            }
            .disabled(hasUnsavedChanges)
        } label: {
            Image(systemName: "plus")
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .help(hasUnsavedChanges ? "请先保存当前修改" : "添加技能文件")
        .accessibilityLabel("添加技能文件")
    }

    private func librarySectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, DesignSpacing.xs)
    }

    private func documentRow(_ document: SkillDocument) -> some View {
        let isSelected = selection == document.id

        return Button {
            requestSelection(document.id)
        } label: {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: document.kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected
                                  ? Color.accentColor.opacity(0.14)
                                  : Color.secondary.opacity(0.09))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(document.kind.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected && hasUnsavedChanges {
                    Circle()
                        .fill(.orange)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel("有未保存的修改")
                }
            }
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("在访达中显示", systemImage: "folder") {
                reveal(document)
            }
            Divider()
            Button("删除", systemImage: "trash", role: .destructive) {
                pendingDeletion = document.id
            }
        }
        .accessibilityLabel(document.name)
        .accessibilityValue(isSelected ? "已选择" : document.kind.subtitle)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
            value: isSelected
        )
    }

    private var missingAgentRow: some View {
        Button {
            onImportAgent()
        } label: {
            HStack(spacing: DesignSpacing.sm) {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加 agent.md")
                        .font(.system(size: 13, weight: .medium))
                    Text("定义模型如何使用技能")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, DesignSpacing.sm)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var emptySkillsRow: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text("还没有扩展技能")
                .font(.subheadline.weight(.medium))
            Text("新建一个模板，或导入已有的 Markdown 文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("新建第一个技能") {
                isShowingCreateSheet = true
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, DesignSpacing.sm)
        .padding(.vertical, DesignSpacing.md)
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorArea: some View {
        if let document = selectedDocument {
            VStack(spacing: 0) {
                editorHeader(document)
                Divider()
                editorContent(document)
                Divider()
                editorFooter(document)
            }
        } else {
            ContentUnavailableView {
                Label("选择一个技能文件", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("从左侧选择文件以查看和编辑内容。")
            } actions: {
                Button("新建 skill.md") {
                    isShowingCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
                Button("导入文件", action: onImportSkills)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func editorHeader(_ document: SkillDocument) -> some View {
        HStack(spacing: DesignSpacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DesignSpacing.sm) {
                    Text(document.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    if hasUnsavedChanges {
                        Label("已修改", systemImage: "circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .labelStyle(CompactStatusLabelStyle())
                    }
                }

                Text(document.kind.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DesignSpacing.md)

            Picker("显示方式", selection: $editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 156)

            Menu {
                Button("在访达中显示", systemImage: "folder") {
                    reveal(document)
                }

                if document.kind == .agent {
                    Button("替换 agent.md…", systemImage: "doc.badge.arrow.up") {
                        onImportAgent()
                    }
                    .disabled(hasUnsavedChanges)

                    Button("生成示例", systemImage: "wand.and.stars") {
                        isShowingGenerateConfirmation = true
                    }
                    .disabled(hasUnsavedChanges)
                }

                Divider()

                Button("删除文件", systemImage: "trash", role: .destructive) {
                    pendingDeletion = document.id
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("更多文件操作")
        }
        .padding(.horizontal, DesignSpacing.xl)
        .padding(.vertical, DesignSpacing.md)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.bar))
    }

    @ViewBuilder
    private func editorContent(_ document: SkillDocument) -> some View {
        switch editorMode {
        case .source:
            ZStack(alignment: .topLeading) {
                if draftContent.isEmpty {
                    Text("在这里编写 Markdown…")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, DesignSpacing.lg + 5)
                        .padding(.vertical, DesignSpacing.lg + 2)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $draftContent)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(3)
                    .padding(DesignSpacing.md)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .accessibilityLabel("编辑 \(document.name)")
            }
        case .preview:
            ScrollView {
                MarkdownPreview(source: draftContent)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignSpacing.xxl)
                    .padding(.vertical, DesignSpacing.xl)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                if draftContent.isEmpty {
                    ContentUnavailableView(
                        "没有可预览的内容",
                        systemImage: "doc.plaintext",
                        description: Text("切换到编辑模式开始编写。")
                    )
                }
            }
        }
    }

    private func editorFooter(_ document: SkillDocument) -> some View {
        HStack(spacing: DesignSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text("\(lineCount) 行 · \(draftContent.count) 个字符 · 修改于 \(document.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: DesignSpacing.md)

            Button("还原") {
                draftContent = savedContent
            }
            .disabled(!hasUnsavedChanges)

            Button("保存") {
                _ = saveCurrentDocument()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasUnsavedChanges)
        }
        .padding(.horizontal, DesignSpacing.xl)
        .padding(.vertical, DesignSpacing.md)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.bar))
    }

    // MARK: - Data

    private var documents: [SkillDocument] {
        var result: [SkillDocument] = []
        if let agentDocument { result.append(agentDocument) }
        result.append(contentsOf: skillDocuments)
        return result
    }

    private var agentDocument: SkillDocument? {
        guard let agentFile else { return nil }
        return SkillDocument(
            id: .agent,
            name: agentFile.name,
            path: agentFile.path,
            kind: .agent,
            fallbackDate: agentFile.updatedAt
        )
    }

    private var skillDocuments: [SkillDocument] {
        skillFiles.map { skill in
            SkillDocument(
                id: .skill(skill.id),
                name: skill.name,
                path: skill.path,
                kind: .skill,
                fallbackDate: skill.addedAt
            )
        }
    }

    private var documentIDs: [SkillDocument.ID] {
        documents.map(\.id)
    }

    private var selectedDocument: SkillDocument? {
        document(for: selection)
    }

    private var hasUnsavedChanges: Bool {
        draftContent != savedContent
    }

    private var lineCount: Int {
        draftContent.isEmpty ? 0 : draftContent.components(separatedBy: .newlines).count
    }

    private func document(for id: SkillDocument.ID?) -> SkillDocument? {
        guard let id else { return nil }
        return documents.first(where: { $0.id == id })
    }

    private func reconcileSelection() {
        if let selection, document(for: selection) != nil { return }
        guard let first = documents.first else {
            selection = nil
            draftContent = ""
            savedContent = ""
            return
        }
        selectImmediately(first.id)
    }

    private func requestSelection(_ id: SkillDocument.ID) {
        guard id != selection else { return }
        if hasUnsavedChanges {
            pendingSelection = id
            isShowingUnsavedAlert = true
        } else {
            selectImmediately(id)
        }
    }

    private func continuePendingSelection() {
        guard let pendingSelection else { return }
        self.pendingSelection = nil
        selectImmediately(pendingSelection)
    }

    private func selectImmediately(_ id: SkillDocument.ID) {
        guard let document = document(for: id) else { return }
        selection = id
        load(document)
    }

    private func load(_ document: SkillDocument) {
        guard let content = onReadFile(document.path) else { return }
        savedContent = content
        draftContent = content
    }

    @discardableResult
    private func saveCurrentDocument() -> Bool {
        guard let selection else { return false }
        let succeeded: Bool
        switch selection {
        case .agent:
            succeeded = onSaveAgent(draftContent)
        case let .skill(id):
            succeeded = onSaveSkill(id, draftContent)
        }
        if succeeded { savedContent = draftContent }
        return succeeded
    }

    private func generateAgentTemplate() {
        guard let agent = onGenerateAgent() else { return }
        let document = SkillDocument(
            id: .agent,
            name: agent.name,
            path: agent.path,
            kind: .agent,
            fallbackDate: agent.updatedAt
        )
        selection = .agent
        load(document)
    }

    private func deletePendingDocument() {
        guard let id = pendingDeletion else { return }
        pendingDeletion = nil

        let succeeded: Bool
        switch id {
        case .agent:
            succeeded = onRemoveAgent()
        case let .skill(skillID):
            guard let index = skillFiles.firstIndex(where: { $0.id == skillID }) else { return }
            succeeded = onDeleteSkill(index)
        }

        guard succeeded else { return }

        guard selection == id else { return }
        let next = documents.first(where: { $0.id != id })
        selection = nil
        draftContent = ""
        savedContent = ""
        if let next { selectImmediately(next.id) }
    }

    private func reveal(_ document: SkillDocument) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path)])
    }
}

private struct SkillDocument: Identifiable {
    enum ID: Hashable {
        case agent
        case skill(UUID)
    }

    enum Kind: Equatable {
        case agent
        case skill

        var icon: String {
            switch self {
            case .agent: "cpu"
            case .skill: "hammer"
            }
        }

        var subtitle: String {
            switch self {
            case .agent: "全局代理规则"
            case .skill: "扩展技能"
            }
        }

        var description: String {
            switch self {
            case .agent: "决定模型如何回答、调用工具和选择技能"
            case .skill: "为模型提供特定任务的说明与约束"
            }
        }
    }

    let id: ID
    let name: String
    let path: String
    let kind: Kind
    let fallbackDate: Date

    var modifiedAt: Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date ?? fallbackDate
    }
}

private enum EditorMode: String, CaseIterable, Identifiable {
    case source
    case preview

    var id: String { rawValue }
    var title: String { self == .source ? "编辑" : "预览" }
    var icon: String { self == .source ? "pencil" : "eye" }
}

private struct CompactStatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
                .font(.system(size: 6))
            configuration.title
        }
    }
}

private struct NewSkillFileSheet: View {
    let onCreate: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private var normalizedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasSuffix(".md") ? trimmed : "\(trimmed).md"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.xl) {
            Label("新建技能文件", systemImage: "doc.badge.plus")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                Text("文件名称")
                    .font(.subheadline.weight(.medium))
                TextField("例如：weather", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(create)
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("将保存为 \(normalizedName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建", action: create)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSpacing.xxl)
        .frame(width: 420)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = onCreate(name)
    }
}
