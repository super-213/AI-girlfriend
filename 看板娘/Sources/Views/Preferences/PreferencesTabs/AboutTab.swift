//
//  AboutTab.swift
//  桌面宠物应用
//
//  关于标签页视图
//

import SwiftUI

/// 关于标签页
struct AboutTab: View {
    let currentCharacterName: String
    let onClose: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                // 应用图标
                Image(systemName: "heart.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.pink)
                    .padding(.top, DesignSpacing.xl)
                    .accessibilityLabel("应用图标")
                    .accessibilityHidden(true)

                // 当前角色名称
                Text(currentCharacterName)
                    .font(DesignFonts.title)
                    .foregroundColor(DesignColors.textPrimary)

                // 版本信息
                Text("版本 1.0.0")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)

                // 应用描述
                Text("一个可爱的桌面 AI 伴侣")
                    .font(DesignFonts.body)
                    .foregroundColor(DesignColors.textPrimary)
                    .padding(.top, DesignSpacing.xs)

                Spacer()

                // 关闭按钮
                HStack {
                    Spacer()
                    Button("关闭") {
                        onClose()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .enhancedButtonStyle(isPrimary: false, isDisabled: false)
                    .accessibilityLabel("关闭偏好设置窗口")
                    .accessibilityHint("关闭当前窗口")
                }
                .padding(.horizontal, DesignSpacing.xl)
                .padding(.bottom, DesignSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("关于标签")
    }
}
