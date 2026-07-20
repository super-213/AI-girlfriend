//
//  PetSpeechBubbleView.swift
//  看板娘
//

import SwiftUI

struct PetSpeechBubbleView: View {
    let text: String
    let state: PetActivityState
    let canCancel: Bool
    let onCancel: () -> Void
    let onDismiss: () -> Void
    let onOpenDialog: () -> Void

    private var visibleText: String {
        guard text.count > 900 else { return text }
        return String(text.prefix(900)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label(state.displayName, systemImage: state.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                if canCancel {
                    Button(action: onCancel) {
                        Label("停止", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                    }
                    .help("停止生成")
                }
                Button(action: onOpenDialog) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("打开完整对话")
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .help("收起")
            }
            .buttonStyle(.plain)

            ScrollView {
                Text(visibleText)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(perform: onOpenDialog)
            }
            .frame(maxHeight: 132)
        }
        .foregroundStyle(.primary)
        .padding(13)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 16, y: 7)
        .petInteractiveRegion()
    }

    private var tint: Color {
        switch state {
        case .error: return .red
        case .success: return .green
        case .waitingForConfirmation, .needsInput: return .orange
        default: return .blue
        }
    }
}
