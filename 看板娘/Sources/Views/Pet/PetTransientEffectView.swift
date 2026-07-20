//
//  PetTransientEffectView.swift
//  看板娘
//

import SwiftUI

struct PetTransientEffectView: View {
    let state: PetActivityState
    let effect: PetTransientEffect?
    @State private var animate = false

    var body: some View {
        ZStack {
            if state == .sleeping {
                Text("z Z")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo)
                    .offset(x: 78, y: -82)
                    .opacity(animate ? 0.25 : 1)
                    .offset(y: animate ? -10 : 0)
            }
            if effect == .success {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(.yellow)
                    .scaleEffect(animate ? 1.25 : 0.7)
                    .opacity(animate ? 0.15 : 1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: true)) { animate = true }
        }
    }
}
