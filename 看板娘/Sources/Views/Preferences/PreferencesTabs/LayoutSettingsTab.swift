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
    @Binding var petHorizontalPlacement: String
    @Binding var sleepMinutes: Double
    @Binding var commandConfirmationStyle: String
    @Binding var bubbleAutoHideDuration: Double
    
    let onSave: () -> Void
    let onCancel: () -> Void
    let hasUnsavedChanges: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                Text("调整界面重叠比例")
                    .font(DesignFonts.headline)
                    .padding(.top, DesignSpacing.md)
                
                // 预览区域
                OverlapPreview(
                    overlapRatio: overlapRatio,
                    horizontalPlacement: PetHorizontalPlacement(rawValue: petHorizontalPlacement) ?? .defaultValue
                )
                    .frame(height: 180)
                    .padding(.horizontal, DesignSpacing.lg)
                
                // 滑块控制
                OverlapSliderControl(overlapRatio: $overlapRatio)
                    .padding(.horizontal, DesignSpacing.xl)

                Divider().padding(.horizontal, DesignSpacing.xl)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("桌宠水平位置")
                        Picker("桌宠水平位置", selection: $petHorizontalPlacement) {
                            ForEach(PetHorizontalPlacement.allCases) { placement in
                                Label(placement.displayName, systemImage: placement.systemImage)
                                    .tag(placement.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    HStack {
                        Text("空闲休息")
                        Spacer()
                        Text(sleepMinutes == 0 ? "关闭" : "\(Int(sleepMinutes)) 分钟")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $sleepMinutes, in: 0...30, step: 1)

                    Picker("命令确认方式", selection: $commandConfirmationStyle) {
                        Text("宠物附近确认卡片").tag("nearPet")
                        Text("系统确认弹窗").tag("systemAlert")
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Text("气泡自动收起")
                        Spacer()
                        Text("\(Int(bubbleAutoHideDuration)) 秒")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $bubbleAutoHideDuration, in: 5...60, step: 5)
                }
                .padding(.horizontal, DesignSpacing.xl)
                
                Spacer()
                
                EnhancedActionButtons(
                    onSave: onSave,
                    onCancel: onCancel,
                    isSaveDisabled: false,
                    hasUnsavedChanges: hasUnsavedChanges
                )
                .padding(.horizontal, DesignSpacing.xl)
                .padding(.bottom, DesignSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局设置标签")
    }
}
