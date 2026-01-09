//
//  PreferencesModels.swift
//  桌面宠物应用
//
//  偏好设置相关的数据模型、验证逻辑和UI组件
//

import Foundation
import SwiftUI
import AppKit

// MARK: - 验证错误

/// 验证错误枚举，定义所有可能的验证错误类型
enum ValidationError: LocalizedError {
    case emptyAPIKey
    case invalidAPIKey
    case invalidURL
    case emptyModel
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            return "API 密钥不能为空"
        case .invalidAPIKey:
            return "API 密钥格式无效或为默认值"
        case .invalidURL:
            return "API 地址必须是有效的 HTTPS URL"
        case .emptyModel:
            return "模型名称不能为空"
        case .networkError(let message):
            return "网络错误: \(message)"
        }
    }
}


// MARK: - 偏好设置数据

/// 偏好设置数据结构体，封装所有设置数据
struct PreferencesData: Equatable {
    var apiKey: String
    var aiModel: String
    var systemPrompt: String
    var apiUrl: String
    var provider: String
    var overlapRatio: Double
    var staticMessages: [String]
    
    static let `default` = PreferencesData(
        apiKey: "",
        aiModel: "glm-4v-flash",
        systemPrompt: "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。",
        apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        provider: "zhipu",
        overlapRatio: 0.3,
        staticMessages: []
    )
}


// MARK: - 验证状态

/// 验证状态结构体，管理所有字段的验证逻辑
struct ValidationState {
    var apiKeyError: String?
    var apiUrlError: String?
    var modelError: String?
    
    /// 检查所有字段是否有效
    var isValid: Bool {
        apiKeyError == nil && apiUrlError == nil && modelError == nil
    }
    
    @discardableResult
    mutating func validateAPIKey(_ key: String) -> Bool {
        guard !key.isEmpty else {
            apiKeyError = ValidationError.emptyAPIKey.errorDescription
            return false
        }
        apiKeyError = nil
        return true
    }
    
    @discardableResult
    mutating func validateAPIURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty else {
            apiUrlError = ValidationError.invalidURL.errorDescription
            return false
        }
        apiUrlError = nil
        return true
    }
    
    @discardableResult
    mutating func validateModel(_ model: String) -> Bool {
        guard !model.isEmpty else {
            modelError = ValidationError.emptyModel.errorDescription
            return false
        }
        let validPattern = "^[a-zA-Z0-9_-]+$"
        guard model.range(of: validPattern, options: .regularExpression) != nil else {
            modelError = ValidationError.emptyModel.errorDescription
            return false
        }
        modelError = nil
        return true
    }
    
    /// 清除所有验证错误
    mutating func clearErrors() {
        apiKeyError = nil
        apiUrlError = nil
        modelError = nil
    }
}


// MARK: - 布局常量

/// 布局常量，定义统一的间距和尺寸
struct LayoutConstants {
    static let sectionSpacing: CGFloat = 20
    static let fieldSpacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 20
    static let textFieldWidth: CGFloat = 360
    static let textEditorMinHeight: CGFloat = 100
    static let systemPromptHeight: CGFloat = 180
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
}


// MARK: - 系统提示词编辑器组件

/// 系统提示词编辑器组件
/// 支持多行编辑、字符计数和重置功能
struct SystemPromptEditor: View {
    /// 绑定的文本内容
    @Binding var text: String
    
    /// 字符数限制
    let characterLimit: Int = 500
    
    /// 默认提示词
    let defaultPrompt: String
    
    /// 聚焦字段绑定
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    /// 当前字符数
    var characterCount: Int {
        text.count
    }
    
    /// 是否超过字符限制
    var isOverLimit: Bool {
        characterCount > characterLimit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            // 标签和字符计数
            HStack {
                Text("系统提示词:")
                    .font(DesignFonts.body)
                
                Spacer()
                
                Text("[\(characterCount)/\(characterLimit)]")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(isOverLimit ? DesignColors.warning : .secondary)
                    .accessibilityLabel("字符计数：\(characterCount) 个，限制 \(characterLimit) 个")
            }
            
            // 文本编辑器
            TextEditor(text: $text)
                .frame(height: LayoutConstants.systemPromptHeight)
                .border(DesignColors.border, width: LayoutConstants.borderWidth)
                .font(DesignFonts.input)
                .focused(focusedField, equals: .systemPrompt)
                .accessibilityLabel("系统提示词文本编辑器")
                .accessibilityValue(text)
            
            // 超长警告
            if isOverLimit {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("提示词较长，建议精简以获得更好的响应")
                        .font(DesignFonts.caption)
                }
                .foregroundColor(DesignColors.warning)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("警告：提示词较长，建议精简")
            }
            
            // 重置按钮
            Button(action: resetToDefault) {
                Text("重置为默认")
                    .font(.caption)
            }
            .accessibilityLabel("重置系统提示词为默认值")
            .accessibilityHint("将系统提示词恢复为默认设置")
        }
    }
    
    /// 重置为默认提示词
    func resetToDefault() {
        text = defaultPrompt
    }
}


// MARK: - 服务提供商模型

/// 服务提供商数据模型
struct Provider: Identifiable {
    let id: String
    let name: String
}


// MARK: - 提供商选择器组件

/// 提供商选择器组件
/// 用于选择AI服务提供商（智谱清言或通义千问）
struct ProviderPicker: View {
    /// 选中的提供商ID
    @Binding var selectedProvider: String
    
    /// 可用的提供商列表
    let providers: [Provider] = [
        Provider(id: "zhipu", name: "智谱清言"),
        Provider(id: "qwen", name: "通义千问")
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


// MARK: - 增强表单组件

/// 增强的表单字段组件
/// 支持标签、内容、错误消息和成功消息，提供丰富的视觉反馈
struct EnhancedFormField<Content: View>: View {
    /// 字段标签
    let label: String
    
    /// 错误消息（可选）
    let errorMessage: String?
    
    /// 成功消息（可选）
    let successMessage: String?
    
    /// 字段内容
    let content: Content
    
    /// 是否显示成功状态
    @State private var showSuccess: Bool = false
    
    /// 初始化增强表单字段
    /// - Parameters:
    ///   - label: 字段标签
    ///   - errorMessage: 错误消息
    ///   - successMessage: 成功消息
    ///   - content: 字段内容视图构建器
    init(
        label: String,
        errorMessage: String? = nil,
        successMessage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.errorMessage = errorMessage
        self.successMessage = successMessage
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            Text(label)
                .font(DesignFonts.headline)
            
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 2)
                )
                .animation(DesignAnimation.gentle, value: errorMessage)
                .animation(DesignAnimation.gentle, value: successMessage)
            
            // 错误消息
            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(DesignFonts.caption)
                }
                .foregroundColor(DesignColors.error)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // 成功指示器
            if let successMessage = successMessage, showSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text(successMessage)
                        .font(DesignFonts.caption)
                }
                .foregroundColor(DesignColors.success)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .onChange(of: successMessage) { _, newValue in
            if newValue != nil {
                withAnimation(DesignAnimation.spring) {
                    showSuccess = true
                }
                // 2 秒后自动消失
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(DesignAnimation.gentle) {
                        showSuccess = false
                    }
                }
            } else {
                showSuccess = false
            }
        }
    }
    
    /// 根据状态计算边框颜色
    private var borderColor: Color {
        if errorMessage != nil {
            return DesignColors.borderError
        } else if successMessage != nil && showSuccess {
            return DesignColors.success
        } else {
            return .clear
        }
    }
}


/// 增强的操作按钮组组件
/// 提供保存和取消按钮，包含未保存更改的脉动指示器
struct EnhancedActionButtons: View {
    /// 保存按钮回调
    let onSave: () -> Void
    
    /// 取消按钮回调
    let onCancel: () -> Void
    
    /// 保存按钮是否禁用
    let isSaveDisabled: Bool
    
    /// 是否有未保存的更改
    let hasUnsavedChanges: Bool
    
    /// 脉动动画状态
    @State private var pulseAnimation: CGFloat = 1.0
    
    var body: some View {
        HStack(spacing: DesignSpacing.md) {
            // 未保存更改指示器
            if hasUnsavedChanges {
                HStack(spacing: 4) {
                    Circle()
                        .fill(DesignColors.warning)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulseAnimation)
                        .animation(
                            Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                    Text("未保存的更改")
                        .font(DesignFonts.caption)
                        .foregroundColor(.secondary)
                }
                .transition(.opacity.combined(with: .scale))
                .onAppear {
                    pulseAnimation = 1.3
                }
                .onDisappear {
                    pulseAnimation = 1.0
                }
            }
            
            Spacer()
            
            Button("取消") {
                onCancel()
            }
            .buttonStyle(PlainButtonStyle())
            .enhancedButtonStyle(isPrimary: false, isDisabled: false)
            
            Button("保存") {
                onSave()
            }
            .buttonStyle(PlainButtonStyle())
            .enhancedButtonStyle(isPrimary: true, isDisabled: isSaveDisabled)
            .disabled(isSaveDisabled)
        }
    }
}


/// 增强的成功横幅组件
/// 显示操作成功的反馈，包含从顶部滑入的动画
struct EnhancedSuccessBanner: View {
    /// 成功消息文本
    let message: String
    
    /// 垂直偏移量
    @State private var offset: CGFloat = -100
    
    /// 透明度
    @State private var opacity: Double = 0
    
    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
                .font(.title3)
            Text(message)
                .foregroundColor(.white)
                .font(DesignFonts.body)
        }
        .padding(.horizontal, DesignSpacing.lg)
        .padding(.vertical, DesignSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DesignColors.success)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(DesignAnimation.spring) {
                offset = 8
                opacity = 1
            }
        }
    }
}


// MARK: - 静态提示词编辑器组件

/// 静态提示词列表编辑器组件
/// 支持添加、编辑和删除静态提示词
struct StaticMessagesEditor: View {
    /// 绑定的静态提示词列表
    @Binding var messages: [String]
    
    /// 新消息输入文本
    @State private var newMessage: String = ""
    
    /// 当前编辑的消息索引
    @State private var editingIndex: Int? = nil
    
    /// 编辑中的消息文本
    @State private var editingText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            // 标签和计数
            HStack {
                Text("静态提示词:")
                    .font(DesignFonts.body)
                
                Spacer()
                
                Text("[\(messages.count) 条]")
                    .font(DesignFonts.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            
            // 消息列表
            if !messages.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            HStack(alignment: .top, spacing: 8) {
                                // 序号
                                Text("\(index + 1).")
                                    .font(DesignFonts.input)
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, alignment: .trailing)
                                
                                // 消息内容或编辑框
                                if editingIndex == index {
                                    TextField("编辑消息", text: $editingText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(DesignFonts.input)
                                } else {
                                    Text(message)
                                        .font(DesignFonts.input)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(6)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                
                                // 操作按钮
                                HStack(spacing: 4) {
                                    if editingIndex == index {
                                        // 保存按钮
                                        Button(action: {
                                            messages[index] = editingText
                                            editingIndex = nil
                                            editingText = ""
                                        }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        // 取消按钮
                                        Button(action: {
                                            editingIndex = nil
                                            editingText = ""
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.gray)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    } else {
                                        // 编辑按钮
                                        Button(action: {
                                            editingIndex = index
                                            editingText = message
                                        }) {
                                            Image(systemName: "pencil.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        // 删除按钮
                                        Button(action: {
                                            messages.remove(at: index)
                                        }) {
                                            Image(systemName: "trash.circle")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(height: 150)
                .border(DesignColors.border, width: LayoutConstants.borderWidth)
            } else {
                Text("暂无静态提示词，请添加")
                    .font(DesignFonts.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .border(DesignColors.border, width: LayoutConstants.borderWidth)
            }
            
            // 添加新消息
            HStack(spacing: 8) {
                TextField("输入新的静态提示词", text: $newMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(DesignFonts.input)
                
                Button(action: addMessage) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Text("静态提示词将替代角色的默认自动消息")
                .font(DesignFonts.caption)
                .foregroundColor(.secondary)
        }
    }
    
    /// 添加新消息
    private func addMessage() {
        let trimmed = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(trimmed)
        newMessage = ""
    }
}


// MARK: - 预览组件

/// 重叠预览组件
/// 显示chatOutput和petImage的重叠效果预览
struct OverlapPreview: View {
    /// 重叠比例（0.0-1.0）
    let overlapRatio: Double
    
    var body: some View {
        GeometryReader { geometry in
            let _ = geometry.size.height // 目前没用到
            let inputHeight: CGFloat = 24
            let chatHeight: CGFloat = 60
            let petHeight: CGFloat = 80
            let inputChatSpacing: CGFloat = 8  // inputField 和 chatOutput 之间的间距
            let noOverlapSpacing: CGFloat = 30  // 0% 时的间距（30像素）
            let maxOverlap = chatHeight + noOverlapSpacing  // 最大重叠量（从30px间距到完全重叠）
            let overlapAmount = maxOverlap * overlapRatio
            
            VStack(spacing: 0) {
                // 顶部空白区域
                Spacer()
                
                // 输入框预览（淡蓝色）
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.15))
                    .frame(height: inputHeight)
                    .overlay(
                        Text("输入框")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                    )
                    .padding(.horizontal, DesignSpacing.lg)
                
                // inputField 和 chatOutput 之间的间距
                Spacer().frame(height: inputChatSpacing)
                
                // 重叠区域容器
                ZStack(alignment: .top) {
                    // chatOutput 预览（淡蓝色）
                    VStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.15))
                            .frame(height: chatHeight)
                            .overlay(
                                VStack(spacing: 4) {
                                    Text("对话输出区域")
                                        .font(DesignFonts.caption)
                                        .foregroundColor(DesignColors.textPrimary)
                                    Text("Chat Output")
                                        .font(.system(size: 10))
                                        .foregroundColor(DesignColors.textSecondary)
                                }
                            )
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        
                        Spacer()
                    }
                    
                    // petImage 预览（淡橙色）
                    VStack {
                        // 从 chatHeight + 30px 开始，随着 overlapRatio 增加而减少间距
                        Spacer().frame(height: chatHeight + noOverlapSpacing - overlapAmount)
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.2))
                            .frame(height: petHeight)
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "heart.fill")
                                        .font(.title3)
                                        .foregroundColor(.orange)
                                    Text("宠物图像")
                                        .font(DesignFonts.caption)
                                        .foregroundColor(DesignColors.textPrimary)
                                }
                            )
                            .shadow(color: .orange.opacity(0.2), radius: 4, x: 0, y: 2)
                        
                        Spacer()
                    }
                }
                .frame(height: chatHeight + noOverlapSpacing - overlapAmount + petHeight)
                .padding(.horizontal, DesignSpacing.lg)
                
                Spacer()
            }
        }
    }
}

