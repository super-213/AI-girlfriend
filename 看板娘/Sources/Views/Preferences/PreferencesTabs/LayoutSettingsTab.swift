//
//  LayoutSettingsTab.swift
//  桌面宠物应用
//
//  布局设置标签页视图
//

import SwiftUI

/// 布局设置标签页
struct LayoutSettingsTab: View {
    @Binding var overlapRatio: Double
    @Binding var petHorizontalPosition: Double
    @Binding var petContentScale: Double
    @Binding var sleepMinutes: Double
    @Binding var commandConfirmationStyle: String
    @Binding var bubbleAutoHideDuration: Double

    let character: PetCharacter
    let onSave: () -> Void
    let onCancel: () -> Void
    let hasUnsavedChanges: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSpacing.xl) {
                pageHeader

                OverlapPreview(
                    overlapRatio: $overlapRatio,
                    horizontalPosition: $petHorizontalPosition,
                    contentScale: $petContentScale,
                    character: character
                )
                .frame(height: 380)

                behaviorSection

                EnhancedActionButtons(
                    onSave: onSave,
                    onCancel: onCancel,
                    isSaveDisabled: false,
                    hasUnsavedChanges: hasUnsavedChanges
                )
                .padding(.top, DesignSpacing.xs)
                .padding(.bottom, DesignSpacing.lg)
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, DesignSpacing.xxl)
            .padding(.top, DesignSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局设置标签")
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("布局")
                .font(.system(size: 22, weight: .semibold))
            Text("直接在预览中拖动桌宠调整位置，捏合或使用按钮改变大小。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        SettingsCard(title: "界面行为", systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                settingTitle(
                    "空闲休息",
                    detail: sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟"
                )
                Slider(value: $sleepMinutes, in: 0...30, step: 1)
                    .accessibilityValue(sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟")
            }

            Divider()

            HStack(spacing: DesignSpacing.lg) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("命令确认")
                        .font(.system(size: 13, weight: .medium))
                    Text("需要执行系统命令时的确认位置")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("命令确认方式", selection: $commandConfirmationStyle) {
                    Text("宠物附近").tag("nearPet")
                    Text("系统弹窗").tag("systemAlert")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            Divider()

            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                settingTitle("气泡自动收起", detail: "\(Int(bubbleAutoHideDuration)) 秒")
                Slider(value: $bubbleAutoHideDuration, in: 5...60, step: 5)
                    .accessibilityValue("\(Int(bubbleAutoHideDuration)) 秒")
            }
        }
    }

    private func settingTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(detail)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }
}

private struct SettingsCard<Content: View>: View {
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
