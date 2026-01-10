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
    
    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.title3)
            Text(message)
                .foregroundColor(.white)
                .font(DesignFonts.body)
        }
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignColors.success)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(DesignAnimation.spring) {
                offset = 8
                opacity = 1
            }
        }
    }
}
