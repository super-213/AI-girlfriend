//
//  PetConfirmationCardView.swift
//  看板娘
//

import AppKit
import SwiftUI

struct PetConfirmationCardView: View {
    let command: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("等待执行确认", systemImage: "exclamationmark.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            ScrollView(.horizontal) {
                Text(command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(9)
            }
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 72)
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))

            HStack {
                Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string) }
                    .buttonStyle(.plain)
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                Button("执行", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.orange.opacity(0.4)))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        .petInteractiveRegion()
    }
}
