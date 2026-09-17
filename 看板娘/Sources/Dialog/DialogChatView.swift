//
//  DialogChatView.swift
//  看板娘
//
//  Ctrl + T 原生双栏对话窗口
//

import AppKit
import SwiftUI

struct DialogChatView: View {
    @ObservedObject var viewModel: DialogChatViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isInputFocused = false
    @State private var inputEditorHeight: CGFloat = DialogTextEditor.minimumHeight
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isFileDropTargeted = false
    @AppStorage(AgentWorkspaceSettings.showCloudTransferNoticeKey) private var showCloudTransferNotice = false
    @AppStorage(AgentWorkspaceSettings.showDirectoryAccessStatusKey) private var showDirectoryAccessStatus = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)
        } detail: {
            chatPane
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.startNewConversation()
                    isInputFocused = true
                } label: {
                    Label("新对话", systemImage: "square.and.pencil")
                }
                .disabled(viewModel.isBusy)
                .help("新对话")
            }
        }
        .onAppear {
            viewModel.refreshCacheStatus()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            viewModel.refreshCacheStatus()
        }
        .onChange(of: viewModel.selectedConversationID) { _, _ in
            inputEditorHeight = DialogTextEditor.minimumHeight
            isInputFocused = true
        }
        .sheet(isPresented: $viewModel.showToolConfirmation) {
            DialogToolConfirmationSheet(
                summary: viewModel.pendingToolSummary,
                onApprove: viewModel.approvePendingTool,
                onDecline: viewModel.declinePendingTool
            )
            .interactiveDismissDisabled()
        }
    }

    private var sidebar: some View {
        List(selection: conversationSelection) {
            Section {
                Button {
                    viewModel.startNewConversation()
                    isInputFocused = true
                } label: {
                    Label("新对话", systemImage: "square.and.pencil")
                }
                .disabled(viewModel.isBusy)
                .help("开始新对话")
            }

            Section("对话历史") {
                ForEach(sortedConversations) { conversation in
                    conversationRow(conversation)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("看板娘")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Label("Control–T 随时唤起", systemImage: "keyboard")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.bar)
        }
    }

    private func conversationRow(_ conversation: DialogConversation) -> some View {
        let isSelected = conversation.id == viewModel.selectedConversationID

        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                .foregroundStyle(isSelected ? DesignColors.primary : Color.secondary)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                Text(relativeTimestamp(for: conversation.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .tag(conversation.id)
        .disabled(viewModel.isBusy && !isSelected)
        .contextMenu {
            Button("删除对话", systemImage: "trash", role: .destructive) {
                viewModel.deleteConversation(conversation.id)
            }
            .disabled(viewModel.isBusy)
        }
        .accessibilityLabel("对话：\(conversation.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chatPane: some View {
        VStack(spacing: 0) {
            messageArea
            inputArea
        }
        .navigationTitle(viewModel.selectedConversationTitle)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isFileDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(DesignColors.primary, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    .padding(12)
                    .overlay {
                        Label("松开以添加文件", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.attachFiles(urls)
            return !urls.isEmpty
        } isTargeted: { isFileDropTargeted = $0 }
    }

    private var messageArea: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.messages.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(geometry.size.height - 28, 260))
                            .padding(.horizontal, 28)
                    } else {
                        LazyVStack(spacing: 19) {
                            ForEach(viewModel.messages) { message in
                                messageRow(for: message)
                                    .id(message.id)
                                    .transition(
                                        reduceMotion
                                            ? .opacity
                                            : .asymmetric(
                                                insertion: .opacity.combined(with: .offset(y: 7)),
                                                removal: .opacity
                                            )
                                    )
                            }
                        }
                        .frame(maxWidth: 760)
                        .padding(.horizontal, 26)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy, animated: !viewModel.isRequesting)
                }
                .onChange(of: viewModel.messages.last?.content.utf8.count ?? 0) { _, _ in
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: viewModel.isRequesting) { _, isRequesting in
                    if !isRequesting {
                        scrollToBottom(proxy, animated: true)
                    }
                }
                .animation(reduceMotion ? nil : DesignAnimation.spring, value: viewModel.messages.count)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DesignColors.primary.opacity(0.09))
                    .frame(width: 64, height: 64)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(DesignColors.primary.opacity(0.14), lineWidth: 1)
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(DesignColors.primary)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.bottom, 20)

            Text("要和看板娘聊点什么？")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.45)
                .foregroundStyle(.primary)

            Text("问问题、整理想法，或让我帮你完成一个任务。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 9)
                .frame(maxWidth: 360)
        }
        .accessibilityElement(children: .combine)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.queuedMessages.isEmpty {
                queuedMessagesView
            }

            if !viewModel.pendingAttachments.isEmpty {
                PetAttachmentTrayView(
                    attachments: viewModel.pendingAttachments,
                    onRemove: viewModel.removeAttachment,
                    onClear: viewModel.clearAttachments
                )

                if showCloudTransferNotice && AgentWorkspaceSettings.isCloudModel() {
                    Label("附件内容将由当前云端模型处理", systemImage: "icloud.and.arrow.up")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            if showDirectoryAccessStatus && AgentFileAccessStore.shared.requiresAuthorization {
                Label("仅可访问已授权目录和本轮附件", systemImage: "folder.badge.checkmark")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if viewModel.inputText.isEmpty {
                        Text(inputPlaceholder)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(nsColor: .placeholderTextColor))
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }

                    DialogTextEditor(
                        text: $viewModel.inputText,
                        height: $inputEditorHeight,
                        isFocused: $isInputFocused,
                        isEditable: true,
                        onSubmit: viewModel.sendCurrentInput
                    )
                    .frame(height: inputEditorHeight)
                    .accessibilityLabel("消息")
                }

                composerActions
            }

            HStack(spacing: 6) {
                if viewModel.isCompactingContext {
                    Text(queueStatusText(prefix: "正在压缩上下文"))
                } else if viewModel.isExecutingTool {
                    Text(queueStatusText(prefix: "正在执行工具"))
                } else if viewModel.isRequesting {
                    Text(queueStatusText(prefix: "正在生成"))
                } else {
                    Text("↵ 发送")
                    Text("·")
                    Text("⇧↵ 换行")
                }

                Spacer(minLength: 8)

                cacheStatusLabel
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(height: 13)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(composerBackgroundColor)
                .shadow(color: Color.black.opacity(reduceTransparency ? 0.05 : 0.11), radius: 18, y: 7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    isInputFocused ? DesignColors.primary.opacity(0.58) : separatorColor,
                    lineWidth: isInputFocused ? 1.25 : 1
                )
        }
        .frame(maxWidth: 760)
        .padding(.horizontal, 26)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0),
                    Color(nsColor: .windowBackgroundColor).opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1), value: isInputFocused)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
            value: viewModel.queuedMessages.count
        )
    }

    private var queuedMessagesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignColors.primary)

                Text("待发送 · \(viewModel.queuedMessages.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(viewModel.queuedMessages.enumerated()), id: \.element.id) { index, message in
                        queuedMessageRow(message, position: index + 1)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(CGFloat(viewModel.queuedMessages.count) * 34, 106))
        }
        .padding(.bottom, 2)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
    }

    private func queuedMessageRow(_ message: QueuedDialogMessage, position: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(position)")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06), in: Circle())

            Text(message.content)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(message.content)

            Button {
                viewModel.deleteQueuedMessage(message.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(DialogPressButtonStyle())
            .help("从队列中删除")
            .accessibilityLabel("删除待发送消息")
            .accessibilityValue(message.content)
        }
        .padding(.leading, 5)
        .padding(.trailing, 3)
        .frame(height: 30)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var cacheStatusLabel: some View {
        Label(cacheStatusText, systemImage: "memorychip")
            .lineLimit(1)
            .foregroundStyle(viewModel.cacheStatus.cacheHitRatio == nil ? .tertiary : .secondary)
            .contentTransition(.numericText(value: viewModel.cacheStatus.cacheHitRatio ?? 0))
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1),
                value: viewModel.cacheStatus.cacheHitRatio
            )
            .help(cacheStatusHelp)
            .accessibilityLabel("缓存命中率")
            .accessibilityValue(cacheStatusAccessibilityValue)
    }

    private var composerActions: some View {
        HStack(spacing: 6) {
            Button(action: chooseAttachments) {
                Image(systemName: "paperclip")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.075), in: Circle())
            }
            .buttonStyle(DialogPressButtonStyle())
            .help("添加文件或文件夹")
            .accessibilityLabel("添加附件")

            if viewModel.isRequesting && !viewModel.isExecutingTool {
                stopButton
            } else if viewModel.isExecutingTool {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("正在执行工具")
            }

            sendButton
        }
    }

    private var stopButton: some View {
        Button(action: viewModel.stopGenerating) {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.10), in: Circle())
        }
        .buttonStyle(DialogPressButtonStyle())
        .help("停止生成")
        .accessibilityLabel("停止生成")
    }

    private var sendButton: some View {
        Button(action: viewModel.sendCurrentInput) {
            Image(systemName: viewModel.isBusy ? "tray.and.arrow.down" : "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(canSend ? Color(nsColor: .alternateSelectedControlTextColor) : Color.secondary)
                .frame(width: 32, height: 32)
                .background(canSend ? DesignColors.primary : Color.primary.opacity(0.075), in: Circle())
        }
        .buttonStyle(DialogPressButtonStyle())
        .disabled(!canSend)
        .help(viewModel.isBusy ? "加入发送队列" : "发送消息")
        .accessibilityLabel(viewModel.isBusy ? "加入发送队列" : "发送消息")
    }

    private func messageRow(for message: DialogMessage) -> some View {
        let isUser = message.role == .user

        return VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !isUser {
                    Image(systemName: message.role == .tool ? "wrench.and.screwdriver.fill" : "sparkles")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(message.role == .tool ? DesignColors.warning : DesignColors.primary)
                }

                Text(roleLabel(for: message.role))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 3)

            if !message.attachments.isEmpty {
                attachmentHistory(for: message.attachments)
            }

            Group {
                if message.content.isEmpty && viewModel.isRequesting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在思考…")
                            .foregroundStyle(.secondary)
                    }
                } else if message.role == .assistant {
                    SelectableMarkdownText(source: message.content)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 14))
            .lineSpacing(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(messageForeground(for: message.role))
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(messageBackground(for: message.role))
            }
            .overlay {
                if !isUser {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(separatorColor.opacity(0.75), lineWidth: 1)
                }
            }
            .frame(maxWidth: 560, alignment: isUser ? .trailing : .leading)

            ForEach(message.artifacts) { artifact in
                DialogFileResultsCard(artifact: artifact) { paths in
                    viewModel.attachResultFiles(paths)
                    isInputFocused = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var conversationSelection: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedConversationID },
            set: { selection in
                guard let selection else { return }
                viewModel.selectConversation(selection)
                isInputFocused = true
            }
        )
    }

    private var sortedConversations: [DialogConversation] {
        viewModel.conversations.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.pendingAttachments.isEmpty
    }

    private var inputPlaceholder: String {
        if !viewModel.pendingAttachments.isEmpty { return "输入如何分析或处理附件…" }
        return viewModel.isBusy ? "继续输入，回车加入队列…" : "给看板娘发送消息…"
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        viewModel.attachFiles(panel.urls)
        isInputFocused = true
    }

    private func attachmentHistory(for attachments: [LocalFileAttachment]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: attachment.path))
                } label: {
                    Label(attachment.displayName, systemImage: attachment.isDirectory ? "folder.fill" : (attachment.isImage ? "photo.fill" : "doc.fill"))
                        .lineLimit(1)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 27)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(attachment.path)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 560, alignment: .trailing)
    }

    private func queueStatusText(prefix: String) -> String {
        guard !viewModel.queuedMessages.isEmpty else {
            return prefix == "正在生成" ? "正在生成，可随时停止" : prefix
        }
        return "\(prefix) · \(viewModel.queuedMessages.count) 条待发送"
    }

    private var composerBackgroundColor: Color {
        Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : 0.88)
    }

    private var cacheStatusText: String {
        guard let ratio = viewModel.cacheStatus.cacheHitRatio else {
            return "缓存命中 —"
        }
        return "缓存命中 \(ratio.formatted(.percent.precision(.fractionLength(1))))"
    }

    private var cacheStatusAccessibilityValue: String {
        guard let ratio = viewModel.cacheStatus.cacheHitRatio else {
            return "当前模型尚未提供缓存统计"
        }
        return "累计 \(ratio.formatted(.percent.precision(.fractionLength(1))))"
    }

    private var cacheStatusHelp: String {
        let status = viewModel.cacheStatus
        let providerName = ModelProvider(rawValue: status.provider)?.displayName ?? status.provider
        guard let metrics = status.metrics, let ratio = metrics.cacheHitRatio else {
            return "\(providerName) · \(status.model)\n当前模型尚未返回缓存 token 统计。"
        }

        return """
        累计缓存命中率 \(ratio.formatted(.percent.precision(.fractionLength(1))))
        缓存 \(metrics.cachedTokens.formatted()) / \(metrics.measuredPromptTokens.formatted()) 个提示 token
        \(metrics.measuredRequestCount) / \(metrics.requestCount) 次请求提供缓存统计
        \(providerName) · \(status.model)
        """
    }

    private var separatorColor: Color {
        if colorSchemeContrast == .increased {
            return Color(nsColor: .separatorColor)
        }
        return Color.primary.opacity(0.10)
    }

    private func relativeTimestamp(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func roleLabel(for role: DialogMessage.Role) -> String {
        switch role {
        case .user:
            return "你"
        case .assistant:
            return "看板娘"
        case .tool:
            return "工具"
        }
    }

    private func messageBackground(for role: DialogMessage.Role) -> Color {
        switch role {
        case .user:
            return DesignColors.primary
        case .assistant:
            return Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.68)
        case .tool:
            return DesignColors.warning.opacity(0.11)
        }
    }

    private func messageForeground(for role: DialogMessage.Role) -> Color {
        role == .user ? Color(nsColor: .alternateSelectedControlTextColor) : DesignColors.textPrimary
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let lastID = viewModel.messages.last?.id else { return }
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private struct DialogToolConfirmationSheet: View {
    let summary: String
    let onApprove: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("确认操作", systemImage: "checkmark.shield.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignColors.warning)
            Text("执行前请检查计划、受影响路径或内容差异。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal]) {
                Text(summary)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 320)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            HStack {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                }
                Spacer()
                Button("取消", role: .cancel, action: onDecline)
                Button("执行", action: onApprove).buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 260)
    }
}

private struct DialogFileResultsCard: View {
    let artifact: DialogArtifact
    let onAttach: ([String]) -> Void
    @State private var selectedPaths = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(artifact.title, systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("已选 \(selectedPaths.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                ForEach(artifact.files.prefix(50)) { file in
                    HStack(spacing: 9) {
                        Button {
                            if selectedPaths.contains(file.path) { selectedPaths.remove(file.path) }
                            else { selectedPaths.insert(file.path) }
                        } label: {
                            Image(systemName: selectedPaths.contains(file.path) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedPaths.contains(file.path) ? DesignColors.primary : Color.secondary)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name).lineLimit(1)
                            Text(file.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Button("打开") { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }
                            .buttonStyle(.borderless)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                        } label: { Image(systemName: "finder") }
                            .buttonStyle(.borderless)
                            .help("在 Finder 中显示")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
            }

            HStack {
                Button(selectedPaths.count == artifact.files.count ? "取消全选" : "全选") {
                    selectedPaths = selectedPaths.count == artifact.files.count
                        ? [] : Set(artifact.files.map(\.path))
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("添加到输入") { onAttach(Array(selectedPaths)) }
                    .disabled(selectedPaths.isEmpty)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
    }
}

private struct DialogTextEditor: NSViewRepresentable {
    static let minimumHeight: CGFloat = 22
    static let maximumHeight: CGFloat = 112

    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    let isEditable: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: NSRect(
            origin: .zero,
            size: NSSize(width: 0, height: Self.minimumHeight)
        ))
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("消息")

        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.updateHeight(for: textView, in: scrollView)
            if isFocused {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.textColor = isEditable ? .labelColor : .secondaryLabelColor

        DispatchQueue.main.async {
            context.coordinator.updateHeight(for: textView, in: scrollView)
            if isFocused, scrollView.window?.firstResponder !== textView {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DialogTextEditor

        init(parent: DialogTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scrollView = textView.enclosingScrollView else { return }

            parent.text = textView.string
            updateHeight(for: textView, in: scrollView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            if textView.hasMarkedText() {
                return false
            }

            let modifiers = NSApp.currentEvent?.modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []
            if modifiers.contains(.shift) {
                return false
            }

            parent.onSubmit()
            return true
        }

        func updateHeight(for textView: NSTextView, in scrollView: NSScrollView) {
            guard let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }

            let availableWidth = max(scrollView.contentSize.width, 1)
            if textContainer.containerSize.width != availableWidth {
                textContainer.containerSize = NSSize(
                    width: availableWidth,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = ceil(layoutManager.usedRect(for: textContainer).height)
                + textView.textContainerInset.height * 2
            let contentHeight = max(usedHeight, DialogTextEditor.minimumHeight)
            let clampedHeight = min(contentHeight, DialogTextEditor.maximumHeight)

            if abs(parent.height - clampedHeight) > 0.5 {
                parent.height = clampedHeight
            }

            scrollView.hasVerticalScroller = contentHeight > DialogTextEditor.maximumHeight
            textView.frame.size.height = max(contentHeight, clampedHeight)
        }
    }
}

private struct DialogPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
