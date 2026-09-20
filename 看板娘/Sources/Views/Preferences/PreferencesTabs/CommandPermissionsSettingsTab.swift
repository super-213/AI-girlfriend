//
//  CommandPermissionsSettingsTab.swift
//  看板娘
//

import AppKit
import SwiftUI

struct CommandPermissionsSettingsTab: View {
    @AppStorage(CommandPermissionStorage.modeKey) private var storedMode = CommandPermissionStorage.defaultMode.rawValue
    @AppStorage(CommandPermissionStorage.blacklistKey) private var blacklist = CommandPermissionStorage.defaultBlacklist
    @AppStorage(AgentWorkspaceSettings.requireDirectoryAuthorizationKey) private var requireDirectoryAuthorization = false
    @AppStorage(AgentWorkspaceSettings.showCloudTransferNoticeKey) private var showCloudTransferNotice = false
    @AppStorage(AgentWorkspaceSettings.showDirectoryAccessStatusKey) private var showDirectoryAccessStatus = false
    @AppStorage(AgentWorkspaceSettings.showToolAuditInConversationKey) private var showToolAuditInConversation = false
    @AppStorage("commandConfirmationStyle") private var commandConfirmationStyle = "nearPet"
    @StateObject private var fileAccess = AgentFileAccessStore.shared
    @StateObject private var auditStore = AgentToolAuditStore.shared
    @StateObject private var systemPermissions = SystemPermissionCenter()
    @State private var showAllowAllConfirmation = false

    private var selectedMode: CommandPermissionMode {
        CommandPermissionMode(rawValue: storedMode) ?? CommandPermissionStorage.defaultMode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                Text("安全与隐私")
                    .font(.system(size: 22, weight: .semibold))

                permissionNotice
                systemPermissionsCard
                modeCard
                if selectedMode == .blacklist {
                    blacklistCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                fileWorkspaceCard
                auditCard
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, DesignSpacing.xxl)
            .padding(.vertical, DesignSpacing.xl)
            .frame(maxWidth: .infinity)
            .animation(DesignAnimation.spring, value: selectedMode)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("安全与隐私设置")
        .onAppear {
            systemPermissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            systemPermissions.refresh()
        }
        .alert("允许所有命令？", isPresented: $showAllowAllConfirmation) {
            Button("取消", role: .cancel) { }
            Button("允许", role: .destructive) {
                storedMode = CommandPermissionMode.allowAll.rawValue
            }
        } message: {
            Text("Agent 将不再请求确认，并能以你的用户权限修改或删除本机文件、安装软件和启动其他进程。")
        }
    }

    private var systemPermissionsCard: some View {
        CommandPermissionCard(title: "系统权限", systemImage: "lock.shield") {
            Text("这些权限只会在你点击请求时由 macOS 授予；Agent 运行工具时不会反复弹出系统提示。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(SystemPermissionKind.allCases.enumerated()), id: \.element.id) { index, kind in
                    systemPermissionRow(kind)
                    if index < SystemPermissionKind.allCases.count - 1 {
                        Divider().padding(.vertical, DesignSpacing.md)
                    }
                }
            }

            if systemPermissions.accessibilityStatus != .granted
                || systemPermissions.screenRecordingStatus != .granted {
                Label("更改设备控制或录屏权限后，请完全退出并重新打开看板娘。", systemImage: "arrow.clockwise.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func systemPermissionRow(_ kind: SystemPermissionKind) -> some View {
        let status = systemPermissions.status(for: kind)
        return HStack(alignment: .top, spacing: DesignSpacing.md) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignColors.primary)
                .frame(width: 28, height: 28)
                .background(DesignColors.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text(kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(kind.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignSpacing.md)

            VStack(alignment: .trailing, spacing: DesignSpacing.sm) {
                Label(status.title, systemImage: status.systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(systemPermissionStatusColor(status))

                if kind == .automation {
                    Button("管理权限") {
                        systemPermissions.openSettings(for: kind)
                    }
                    .controlSize(.small)
                } else if status == .granted {
                    Button("打开系统设置") {
                        systemPermissions.openSettings(for: kind)
                    }
                    .controlSize(.small)
                } else {
                    HStack(spacing: DesignSpacing.sm) {
                        Button("打开设置") {
                            systemPermissions.openSettings(for: kind)
                        }
                        Button("请求授权") {
                            systemPermissions.request(kind)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.title)，\(status.title)")
    }

    private func systemPermissionStatusColor(_ status: SystemPermissionCenter.Status) -> Color {
        switch status {
        case .granted: return DesignColors.success
        case .notGranted: return DesignColors.warning
        case .perApplication: return DesignColors.info
        }
    }

    private var fileWorkspaceCard: some View {
        CommandPermissionCard(title: "文件与工具", systemImage: "folder.badge.gearshape") {
            Toggle("限制 Agent 仅访问已授权目录", isOn: $requireDirectoryAuthorization)
            Text("拖入的文件会获得本次会话权限；下方目录会持久允许读取和保存结果。")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            if requireDirectoryAuthorization {
                VStack(spacing: 6) {
                    ForEach(fileAccess.authorizedDirectories, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            Text(path).font(.system(size: 11)).lineLimit(1).help(path)
                            Spacer()
                            Button { fileAccess.removeAuthorizedDirectory(path) } label: {
                                Image(systemName: "minus.circle")
                            }.buttonStyle(.plain).help("移除授权")
                        }
                    }
                    if fileAccess.authorizedDirectories.isEmpty {
                        Text("尚未添加目录").font(.system(size: 11)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button("添加授权目录…", systemImage: "folder.badge.plus", action: chooseAuthorizedDirectory)
            }

            Divider()
            Text("可选的会话内提示").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Toggle("云端模型处理附件时显示传输提示", isOn: $showCloudTransferNotice)
            Toggle("在输入区显示目录授权状态", isOn: $showDirectoryAccessStatus)
            Toggle("在对话中显示工具成功记录", isOn: $showToolAuditInConversation)
            Text("这些展示项默认关闭，不影响实际权限、审批和审计记录。")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
    }

    private var auditCard: some View {
        CommandPermissionCard(title: "工具审计", systemImage: "checklist.checked") {
            HStack {
                Text("记录最近的工具请求、批准与结果，无需在对话里持续展示。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("清空", role: .destructive) { auditStore.clear() }
                    .disabled(auditStore.entries.isEmpty)
            }
            if auditStore.entries.isEmpty {
                Text("暂无记录").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 8) {
                    ForEach(auditStore.entries.prefix(30)) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(entry.status == .failed ? Color.red : (entry.status == .succeeded ? Color.green : Color.secondary))
                                .frame(width: 7, height: 7).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.toolName) · \(entry.status.title)").font(.system(size: 11, weight: .semibold))
                                Text(entry.summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func chooseAuthorizedDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "允许访问"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(fileAccess.addAuthorizedDirectory)
    }

    private var permissionNotice: some View {
        HStack(alignment: .top, spacing: DesignSpacing.md) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignColors.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text("本地命令执行已启用")
                    .font(.system(size: 13, weight: .semibold))
                Text("Agent 通过 /bin/zsh 执行命令，并继承当前用户权限。权限策略会立即生效。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignColors.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var modeCard: some View {
        CommandPermissionCard(title: "审批策略", systemImage: "slider.horizontal.3") {
            Picker("命令审批策略", selection: modeSelection) {
                ForEach(CommandPermissionMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            HStack(alignment: .top, spacing: DesignSpacing.sm) {
                Image(systemName: selectedMode.systemImage)
                    .foregroundStyle(selectedMode == .allowAll ? DesignColors.warning : DesignColors.secondary)
                    .frame(width: 18)
                Text(selectedMode.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(selectedMode == .allowAll ? DesignColors.warning : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedMode == .askWhenRisky {
                Text("风险识别采用保守规则：不能明确判断为只读的命令也会询问。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            HStack(spacing: DesignSpacing.lg) {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    Text("命令确认位置")
                        .font(.system(size: 13, weight: .medium))
                    Text("选择审批请求出现在桌宠附近还是系统弹窗中。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("命令确认位置", selection: $commandConfirmationStyle) {
                    Text("宠物附近").tag("nearPet")
                    Text("系统弹窗").tag("systemAlert")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var modeSelection: Binding<String> {
        Binding(
            get: { storedMode },
            set: { newValue in
                if newValue == CommandPermissionMode.allowAll.rawValue,
                   storedMode != CommandPermissionMode.allowAll.rawValue {
                    showAllowAllConfirmation = true
                } else {
                    storedMode = newValue
                }
            }
        )
    }

    private var blacklistCard: some View {
        CommandPermissionCard(title: "命令黑名单", systemImage: "nosign") {
            Text("每行一条、不区分大小写；命令只要包含该文本就会被拒绝。以 # 开头的行视为注释。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $blacklist)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 180)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DesignColors.border, lineWidth: 1)
                }
                .accessibilityLabel("命令黑名单，每行一条规则")

            HStack {
                Text("修改会立即保存")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("恢复默认") {
                    blacklist = CommandPermissionStorage.defaultBlacklist
                }
            }
        }
    }
}

private struct CommandPermissionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.lg) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(DesignSpacing.lg)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignColors.border, lineWidth: 1)
        }
    }
}
