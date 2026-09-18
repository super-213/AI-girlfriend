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
            compactSliderRow(
                title: "空闲休息",
                value: sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟",
                binding: $sleepMinutes,
                range: 0...30,
                step: 1
            )
        }
    }

    private var conversationSection: some View {
        SettingsCard(title: "对话界面", systemImage: "bubble.left.and.bubble.right") {
            HStack(spacing: DesignSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("桌宠对话上下文")
                        .font(.system(size: 13, weight: .medium))
                    Text("超时后自动开始新会话")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: DesignSpacing.md)

                Toggle("不销毁", isOn: conversationNeverExpires)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }

            if petConversationRetentionMinutes > 0 {
                Divider()

                compactSliderRow(
                    title: "保留时长",
                    value: PetConversationRetention.description(for: petConversationRetentionMinutes),
                    binding: conversationRetentionBinding,
                    range: PetConversationRetention.minimumMinutes...PetConversationRetention.maximumMinutes,
                    step: PetConversationRetention.stepMinutes
                )
            }

            Divider()

            compactSliderRow(
                title: "气泡自动收起",
                value: "\(Int(bubbleAutoHideDuration)) 秒",
                binding: $bubbleAutoHideDuration,
                range: 5...60,
                step: 5
            )
        }
    }

    private func compactSliderRow(
        title: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: DesignSpacing.md) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 112, alignment: .leading)

            Slider(value: binding, in: range, step: step)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(value)

            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .frame(width: 64, alignment: .trailing)
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
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            content
        }
        .padding(DesignSpacing.md)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignColors.border, lineWidth: 1)
        }
    }
}
