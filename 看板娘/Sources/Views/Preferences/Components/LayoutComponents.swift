//
//  LayoutComponents.swift
//  桌面宠物应用
//
//  布局设置相关的UI组件
//

import SwiftUI

/// 重叠比例滑块控制
struct OverlapSliderControl: View {
    @Binding var overlapRatio: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            HStack {
                Text("重叠比例:")
                    .font(DesignFonts.body)
                Spacer()
                Text("\(Int(overlapRatio * 100))%")
                    .font(DesignFonts.body.monospacedDigit())
                    .foregroundColor(DesignColors.textSecondary)
            }
            
            Slider(value: $overlapRatio, in: 0...1, step: 0.01)
                .accessibilityLabel("重叠比例滑块")
                .accessibilityValue("\(Int(overlapRatio * 100))%")
            
            HStack {
                Text("0% (不重叠)")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
                Spacer()
                Text("100% (完全重叠)")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)
            }
        }
    }
}

/// 重叠预览组件
struct OverlapPreview: View {
    let overlapRatio: Double
    
    var body: some View {
        GeometryReader { geometry in
            let _ = geometry.size.height
            let inputHeight: CGFloat = 24
            let chatHeight: CGFloat = 60
            let petHeight: CGFloat = 80
            let inputChatSpacing: CGFloat = 8
            let noOverlapSpacing: CGFloat = 30
            let maxOverlap = chatHeight + noOverlapSpacing
            let overlapAmount = maxOverlap * overlapRatio
            
            VStack(spacing: 0) {
                Spacer()
                
                // 输入框预览
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.15))
                    .frame(height: inputHeight)
                    .overlay(
                        Text("输入框")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                    )
                    .padding(.horizontal, DesignSpacing.lg)
                
                Spacer().frame(height: inputChatSpacing)
                
                // 重叠区域容器
                ZStack(alignment: .top) {
                    // chatOutput 预览
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.15))
                            .frame(height: chatHeight)
                            .overlay(
                                VStack(spacing: 4) {
                                    Text("对话输出区域")
                                        .font(DesignFonts.caption)
                                        .foregroundColor(DesignColors.textPrimary)
                                    Text("Chat Output")
                                        .font(.system(size: 10))
                                        .foregroundColor(DesignColors.textSecondary)
                                }
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        
                        Spacer()
                    }
                    
                    // petImage 预览
                    VStack {
                        Spacer().frame(height: chatHeight + noOverlapSpacing - overlapAmount)
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.2))
                            .frame(height: petHeight)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .font(.title3)
                                        .foregroundColor(.orange)
                                    Text("宠物图像")
                                        .font(DesignFonts.caption)
                                        .foregroundColor(DesignColors.textPrimary)
                                }
                            )
                            .shadow(color: .orange.opacity(0.2), radius: 4, x: 0, y: 2)
                        
                        Spacer()
                    }
                }
                .frame(height: chatHeight + noOverlapSpacing - overlapAmount + petHeight)
                .padding(.horizontal, DesignSpacing.lg)
                
                Spacer()
            }
        }
    }
}
