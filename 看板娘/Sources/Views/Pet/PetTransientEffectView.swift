//
//  PetTransientEffectView.swift
//  看板娘
//

import SwiftUI

struct PetTransientEffectView: View {
    let state: PetActivityState
    let effect: PetTransientEffect?

    var body: some View {
        ZStack {
            if state == .sleeping {
                PetSleepingEffectView()
            }
            if effect == .success {
                PetSuccessEffectView()
            }
        }
        .allowsHitTesting(false)
    }
}

/// 动画状态跟随实际可见内容的生命周期，离开休眠状态后会直接销毁，
/// 避免空的特效容器仍在透明窗口中驱动永久动画事务。
private struct PetSleepingEffectView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        Text("z Z")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(.indigo)
            .offset(x: 78, y: -82)
            .opacity(animate ? 0.25 : 1)
            .offset(y: animate ? -10 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}

/// 成功特效只在 `effect == .success` 的短暂窗口内存在；特效消失时，
/// SwiftUI 会连同它的重复动画一起移除。
private struct PetSuccessEffectView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 34))
            .foregroundStyle(.yellow)
            .scaleEffect(animate ? 1.25 : 0.7)
            .opacity(animate ? 0.15 : 1)
            .onAppear {
                guard !reduceMotion else {
                    animate = true
                    return
                }
                withAnimation(.easeOut(duration: 0.8).repeatCount(2, autoreverses: true)) {
                    animate = true
                }
            }
    }
}
