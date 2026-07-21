//
//  PetInputView.swift
//  看板娘
//

import SwiftUI

struct PetInputView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isDisabled: Bool
    let onHover: (Bool) -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            TextField("我会帮助指挥官解决问题！", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 19))
                }
                .buttonStyle(.plain)
                .help("发送")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .disabled(isDisabled)
        .onHover(perform: onHover)
        .petInteractiveRegion()
    }
}
