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
        .frame(
            maxWidth: .infinity,
            minHeight: PetPanelLayoutMetrics.inputHeight,
            maxHeight: PetPanelLayoutMetrics.inputHeight
        )
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

struct PetAttachmentTrayView: View {
    let attachments: [LocalFileAttachment]
    let onRemove: (UUID) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 5) {
                            Image(systemName: attachment.isDirectory ? "folder.fill" : "doc.fill")
                                .foregroundStyle(.secondary)
                            Text(attachment.displayName)
                                .lineLimit(1)
                            Button {
                                onRemove(attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("移除附件")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(.thinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22)))
                        .help(attachment.path)
                    }
                }
            }
            .scrollIndicators(.hidden)

            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("移除全部附件")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.25)))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
        .petInteractiveRegion()
        .accessibilityLabel("已添加 \(attachments.count) 个附件")
    }
}
