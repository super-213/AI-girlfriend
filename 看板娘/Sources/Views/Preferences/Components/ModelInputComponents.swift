//
//  ModelInputComponents.swift
//  桌面宠物应用
//
//  模型设置相关的输入组件
//

import SwiftUI

/// Ollama 使用说明视图
struct OllamaInstructionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Ollama 本地模型使用说明")
                    .font(DesignFonts.body)
                    .fontWeight(.medium)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("1. 确保已安装 Ollama：")
                    .font(DesignFonts.caption)
                Text("   访问 https://ollama.com 下载安装")
                    .font(DesignFonts.caption)
                    .foregroundColor(.secondary)
                
                Text("2. 下载模型（终端执行）：")
                    .font(DesignFonts.caption)
                    .padding(.top, 4)
                Text("   ollama pull qwen2.5")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                
                Text("3. 常用模型：qwen2.5, llama3, gemma2")
                    .font(DesignFonts.caption)
                    .padding(.top, 4)
                
                Text("4. API Key 字段可留空或填任意值")
                    .font(DesignFonts.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
            .padding(.leading, 20)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .frame(width: LayoutConstants.textFieldWidth)
    }
}

/// 模型输入字段
struct ModelInputField: View {
    @Binding var aiModel: String
    let provider: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("模型：")
                .font(DesignFonts.headline)
            TextField(placeholderText, text: $aiModel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: LayoutConstants.textFieldWidth)
                .focused(focusedField, equals: .model)
                .accessibilityLabel("AI 模型名称")
                .accessibilityHint(accessibilityHintText)
        }
    }
    
    private var placeholderText: String {
        switch provider {
        case "zhipu": return "例如: glm-4v-flash"
        case "qwen": return "例如: qwen-turbo"
        default: return "例如: qwen2.5, llama3"
        }
    }
    
    private var accessibilityHintText: String {
        switch provider {
        case "zhipu": return "输入智谱清言的模型名称，例如 glm-4v-flash"
        case "qwen": return "输入通义千问的模型名称，例如 qwen-turbo"
        default: return "输入 Ollama 模型名称，例如 qwen2.5 或 llama3"
        }
    }
}

/// API 地址输入字段
struct APIUrlInputField: View {
    @Binding var apiUrl: String
    let provider: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API 地址：")
                .font(DesignFonts.headline)
            TextField(placeholderText, text: $apiUrl)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: LayoutConstants.textFieldWidth)
                .focused(focusedField, equals: .apiUrl)
                .accessibilityLabel("API 服务地址")
                .accessibilityHint(accessibilityHintText)
        }
    }
    
    private var placeholderText: String {
        switch provider {
        case "zhipu": return "例如: https://open.bigmodel.cn/api/paas/v4/..."
        case "qwen": return "例如: https://dashscope.aliyuncs.com/api/v1/..."
        default: return "例如: http://localhost:11434/api/chat"
        }
    }
    
    private var accessibilityHintText: String {
        provider == "ollama" 
            ? "输入 Ollama 服务地址，默认为 http://localhost:11434/api/chat"
            : "输入 AI 服务的 API 地址，必须是 HTTPS 协议"
    }
}

/// API Key 输入字段
struct APIKeyInputField: View {
    @Binding var apiKey: String
    let provider: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API Key:")
                .font(DesignFonts.headline)
            
            if provider == "ollama" {
                Text("Ollama 本地模型无需 API Key")
                    .font(DesignFonts.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(width: LayoutConstants.textFieldWidth, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(6)
            } else {
                TextEditor(text: $apiKey)
                    .frame(height: LayoutConstants.textEditorMinHeight)
                    .border(DesignColors.border, width: LayoutConstants.borderWidth)
                    .font(DesignFonts.input)
                    .focused(focusedField, equals: .apiKey)
                    .accessibilityLabel("API 密钥")
                    .accessibilityHint("输入您的 API 密钥以访问 AI 服务")
            }
        }
    }
}
