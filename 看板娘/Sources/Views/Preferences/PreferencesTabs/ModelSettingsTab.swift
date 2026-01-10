//
//  ModelSettingsTab.swift
//  桌面宠物应用
//
//  模型设置标签页视图
//

import SwiftUI

/// 模型设置标签页
struct ModelSettingsTab: View {
    @Binding var provider: String
    @Binding var aiModel: String
    @Binding var apiUrl: String
    @Binding var apiKey: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    let onProviderChange: (String) -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let hasUnsavedChanges: Bool
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                // 提供商选择器
                ProviderPicker(selectedProvider: $provider)
                    .accessibilityLabel("AI 服务提供商选择器")
                    .accessibilityHint("选择智谱清言、通义千问或 Ollama 本地模型作为 AI 服务提供商")
                    .focused(focusedField, equals: .provider)
                    .onChange(of: provider) { _, newValue in
                        onProviderChange(newValue)
                    }
                
                // Ollama 使用说明
                if provider == "ollama" {
                    OllamaInstructionsView()
                }
                
                // 模型字段
                ModelInputField(
                    aiModel: $aiModel,
                    provider: provider,
                    focusedField: focusedField
                )
                
                // API 地址字段
                APIUrlInputField(
                    apiUrl: $apiUrl,
                    provider: provider,
                    focusedField: focusedField
                )
                
                // API Key 字段
                APIKeyInputField(
                    apiKey: $apiKey,
                    provider: provider,
                    focusedField: focusedField
                )

                Spacer()

                EnhancedActionButtons(
                    onSave: onSave,
                    onCancel: onCancel,
                    isSaveDisabled: false,
                    hasUnsavedChanges: hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("模型设置标签")
    }
}
