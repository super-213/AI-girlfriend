//
//  PetStatusIndicatorView.swift
//  看板娘
//

import SwiftUI

struct PetStatusIndicatorView: View {
    let state: PetActivityState
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: state.systemImage)
                .symbolEffect(.pulse, options: .repeating, isActive: isPulsing && isAnimated)
            Text(state.displayName)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 0.8))
        .petInteractiveRegion()
        .onAppear { isPulsing = true }
    }

    private var isAnimated: Bool {
        [.thinking, .talking, .working, .automation, .playingAudio].contains(state)
    }

    private var tint: Color {
        switch state {
        case .error: return .red
        case .success: return .green
        case .waitingForConfirmation, .needsInput: return .orange
        case .sleeping: return .indigo
        default: return .blue
        }
    }
}
