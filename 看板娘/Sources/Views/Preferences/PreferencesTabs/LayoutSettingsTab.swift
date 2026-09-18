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
                OverlapPreview(
                    overlapRatio: $overlapRatio,
                    horizontalPosition: $petHorizontalPosition,
                    contentScale: $petContentScale,
                    character: character
                )
                .frame(height: 320)

                compactSettingsSection
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, DesignSpacing.xxl)
            .padding(.top, DesignSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局设置标签")
    }

    private var compactSettingsSection: some View {
        SettingsCard {
            compactSliderRow(
                title: "进入待机状态",
                value: sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟",
                binding: $sleepMinutes,
                range: 0...30,
                step: 1
            )

            Divider()

            HStack(spacing: DesignSpacing.md) {
                Text("对话保留")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 112, alignment: .leading)

                Slider(
                    value: conversationRetentionBinding,
                    in: PetConversationRetention.minimumMinutes...PetConversationRetention.maximumMinutes,
                    step: PetConversationRetention.stepMinutes
                )
                .controlSize(.small)
                .disabled(petConversationRetentionMinutes == 0)
                .accessibilityLabel("对话保留时长")
                .accessibilityValue(conversationRetentionValue)

                Text(conversationRetentionValue)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .frame(width: 64, alignment: .trailing)

                Toggle("永久保留对话", isOn: conversationNeverExpires)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .fixedSize()
            }

            Divider()

            compactSliderRow(
                title: "气泡收起",
                value: "\(Int(bubbleAutoHideDuration)) 秒",
                binding: $bubbleAutoHideDuration,
                range: 5...60,
                step: 5
            )
        }
    }

    private var conversationRetentionValue: String {
        petConversationRetentionMinutes == 0
            ? "永久"
            : PetConversationRetention.description(for: petConversationRetentionMinutes)
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
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
