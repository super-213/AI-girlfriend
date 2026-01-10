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
                OverlapPreview(overlapRatio: overlapRatio)
                    .frame(height: 180)
                    .padding(.horizontal, DesignSpacing.lg)
                
                // 滑块控制
                OverlapSliderControl(overlapRatio: $overlapRatio)
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
