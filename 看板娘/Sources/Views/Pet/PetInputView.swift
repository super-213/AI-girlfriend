//
//  PetInputView.swift
//  看板娘
//

import SwiftUI

struct PetInputView: View {
    @State private var text = ""
    var isFocused: FocusState<Bool>.Binding
    let placeholder: String
    let isDisabled: Bool
    let onHover: (Bool) -> Void
    let onTextPresenceChanged: (Bool) -> Void
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onSubmit(submit)
            if !text.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 19))
                }
                .buttonStyle(.plain)
                .help("发送")
            }
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("取消输入并收起")
            .accessibilityLabel("取消输入并收起")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .disabled(isDisabled)
        .onHover(perform: onHover)
        .onChange(of: text.isEmpty) { oldValue, newValue in
            guard oldValue != newValue else { return }
            onTextPresenceChanged(!newValue)
        }
        .petInteractiveRegion()
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submittedText = text
        text = ""
        onSubmit(submittedText)
    }

    private func cancel() {
        text = ""
        onCancel()
    }
}
