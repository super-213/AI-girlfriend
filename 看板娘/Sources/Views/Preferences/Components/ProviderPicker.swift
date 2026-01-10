//
//  ProviderPicker.swift
//  桌面宠物应用
//
//  提供商选择器组件
//

import SwiftUI

/// 提供商选择器组件
/// 用于选择AI服务提供商（智谱清言、通义千问或Ollama）
struct ProviderPicker: View {
    @Binding var selectedProvider: String
    
    let providers: [Provider] = [
        Provider(id: "zhipu", name: "智谱清言"),
        Provider(id: "qwen", name: "通义千问"),
        Provider(id: "ollama", name: "Ollama 本地")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing / 2) {
            Text("选择平台：")
                .font(DesignFonts.body)
            
            Picker("选择平台", selection: $selectedProvider) {
                ForEach(providers) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: LayoutConstants.textFieldWidth)
            .accessibilityLabel("AI 服务平台选择器")
            .accessibilityValue(providers.first(where: { $0.id == selectedProvider })?.name ?? "")
        }
    }
}
