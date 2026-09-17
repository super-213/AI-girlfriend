//
//  KnowledgeBaseSettingsTab.swift
//  看板娘
//

import AppKit
import SwiftUI

struct KnowledgeBaseSettingsTab: View {
    @StateObject private var registry = KnowledgeBaseRegistry.shared
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var pendingRemoval: KnowledgeBaseReference?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                knowledgeBaseList
                usageGuide
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("知识库")
        .alert("知识库操作失败", isPresented: $showError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "从应用中移除“\(pendingRemoval?.name ?? "知识库")”？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移除目录引用", role: .destructive) {
                if let pendingRemoval { registry.removeReference(pendingRemoval.id) }
                pendingRemoval = nil
            }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("只会移除应用中保存的目录引用，外置目录里的 .kanban-rag 索引不会被删除。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignColors.primary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 5) {
                    Text("外置 RAG 知识库")
                        .font(.title2.weight(.semibold))
                    Text("文档文本、分块和语义向量都保存在你选择的目录中。应用本身只记住目录路径和启用状态。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: chooseDirectory) {
                    Label("添加目录", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var knowledgeBaseList: some View {
        if registry.references.isEmpty {
            ContentUnavailableView {
                Label("还没有知识库", systemImage: "books.vertical")
            } description: {
                Text("选择任意可写目录。首次添加时会在其中创建 .kanban-rag/index.json。")
            } actions: {
                Button("选择知识库目录", action: chooseDirectory)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(spacing: 10) {
                ForEach(registry.references) { reference in
                    knowledgeBaseRow(reference)
                }
            }
        }
    }

    private func knowledgeBaseRow(_ reference: KnowledgeBaseReference) -> some View {
        let summary = summary(for: reference)
        return HStack(spacing: 14) {
            Toggle("", isOn: Binding(
                get: { reference.isEnabled },
                set: { registry.setEnabled(reference.id, enabled: $0) }
            ))
            .labelsHidden()

            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.title3)
                .foregroundStyle(reference.isEnabled ? DesignColors.primary : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(reference.name).font(.headline)
                    Text("\(summary.documents) 份文档 · \(summary.chunks) 个片段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(reference.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([
                    KnowledgeBaseDiskStore.indexURL(
                        for: URL(fileURLWithPath: reference.path, isDirectory: true)
                    )
                ])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示索引")

            Button(role: .destructive) {
                pendingRemoval = reference
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("移除目录引用")
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
    }

    private var usageGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("在 Agent 中使用").font(.headline)
            Label("说“把这段内容加入知识库”，Agent 会调用 add_to_knowledge_base，写入前需要你确认。", systemImage: "square.and.arrow.down")
            Label("说“使用知识库回答…”，或在输入框选择 $knowledge-base-answer Skill。", systemImage: "sparkles")
            Label("可同时启用多个目录进行联合检索；写入时如果有多个启用项，Agent 会询问或指定目标名称。", systemImage: "rectangle.stack")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(16)
        .background(DesignColors.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "添加知识库"
        panel.message = "选择一个或多个外置目录。索引数据将保存在所选目录的 .kanban-rag 子目录中。"
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                do {
                    try registry.registerDirectory(url)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                    break
                }
            }
        }
    }

    private func summary(for reference: KnowledgeBaseReference) -> (documents: Int, chunks: Int) {
        guard let index = try? KnowledgeBaseDiskStore.load(
            from: URL(fileURLWithPath: reference.path, isDirectory: true)
        ) else { return (0, 0) }
        return (index.documents.count, index.documents.reduce(0) { $0 + $1.chunks.count })
    }
}
