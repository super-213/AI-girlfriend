//
//  CommandPermissionsSettingsTab.swift
//  看板娘
//

import SwiftUI

struct CommandPermissionsSettingsTab: View {
    @AppStorage(CommandPermissionStorage.modeKey) private var storedMode = CommandPermissionStorage.defaultMode.rawValue
    @AppStorage(CommandPermissionStorage.blacklistKey) private var blacklist = CommandPermissionStorage.defaultBlacklist
    @State private var showAllowAllConfirmation = false

    private var selectedMode: CommandPermissionMode {
        CommandPermissionMode(rawValue: storedMode) ?? CommandPermissionStorage.defaultMode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                Text("命令权限")
                    .font(.system(size: 22, weight: .semibold))

                permissionNotice
                modeCard

                if selectedMode == .blacklist {
                    blacklistCard
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, DesignSpacing.xxl)
            .padding(.vertical, DesignSpacing.xl)
            .frame(maxWidth: .infinity)
            .animation(DesignAnimation.spring, value: selectedMode)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("命令权限设置")
        .alert("允许所有命令？", isPresented: $showAllowAllConfirmation) {
            Button("取消", role: .cancel) { }
            Button("允许", role: .destructive) {
                storedMode = CommandPermissionMode.allowAll.rawValue
            }
        } message: {
            Text("Agent 将不再请求确认，并能以你的用户权限修改或删除本机文件、安装软件和启动其他进程。")
        }
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
