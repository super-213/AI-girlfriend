//
//  SuccessBanner.swift
//  桌面宠物应用
//
//  成功消息横幅组件
//

import SwiftUI

/// 增强的成功横幅组件
/// 显示操作成功的反馈，包含从顶部滑入的动画
struct EnhancedSuccessBanner: View {
    let message: String
    
    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignColors.success)
                .font(.body)
            Text(message)
                .foregroundStyle(.primary)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    reduceTransparency
                        ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                        : AnyShapeStyle(.regularMaterial)
                )
                .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(reduceTransparency ? 0 : 0.35), lineWidth: 0.5)
        }
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : DesignAnimation.spring) {
                offset = 8
                opacity = 1
            }
        }
    }
}
