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
    @Binding var petConversationRetentionMinutes: Double
    @Binding var bubbleAutoHideDuration: Double

    let character: PetCharacter
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
                .frame(height: 360)

                petBehaviorSection
                conversationSection
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
        VStack(alignment: .leading, spacing: DesignSpacing.xs) {
            Text("桌面与交互")
                .font(.system(size: 22, weight: .semibold))
            Text("调整桌宠在桌面上的位置与日常交互行为，更改会自动保存。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var petBehaviorSection: some View {
        SettingsCard(title: "桌宠行为", systemImage: "sparkles") {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                settingTitle(
                    "空闲休息",
                    detail: sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟"
                )
                Slider(value: $sleepMinutes, in: 0...30, step: 1)
                    .accessibilityValue(sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟")
            }
        }
    }

    private var conversationSection: some View {
        SettingsCard(title: "对话界面", systemImage: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                HStack(spacing: DesignSpacing.lg) {
                    VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                        Text("桌宠对话上下文")
                            .font(.system(size: 13, weight: .medium))
                        Text("超过设定时间没有继续对话时，自动开始新会话。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("不销毁", isOn: conversationNeverExpires)
                        .toggleStyle(.switch)
                        .fixedSize()
                }

                if petConversationRetentionMinutes > 0 {
                    settingTitle(
                        "保留时长",
                        detail: PetConversationRetention.description(for: petConversationRetentionMinutes)
                    )
                    Slider(
                        value: conversationRetentionBinding,
                        in: PetConversationRetention.minimumMinutes...PetConversationRetention.maximumMinutes,
                        step: PetConversationRetention.stepMinutes
                    )
                    .accessibilityValue(PetConversationRetention.description(for: petConversationRetentionMinutes))
                }
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

    private var conversationNeverExpires: Binding<Bool> {
        Binding(
            get: { petConversationRetentionMinutes == 0 },
            set: { neverExpires in
                petConversationRetentionMinutes = neverExpires
                    ? 0
                    : PetConversationRetention.defaultMinutes
            }
        )
    }

    private var conversationRetentionBinding: Binding<Double> {
        Binding(
            get: {
                max(petConversationRetentionMinutes, PetConversationRetention.minimumMinutes)
            },
            set: { petConversationRetentionMinutes = PetConversationRetention.normalized($0) }
        )
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
