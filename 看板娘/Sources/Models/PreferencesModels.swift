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
    
    static let `default` = PreferencesData(
        apiKey: "",
        aiModel: "glm-4v-flash",
        systemPrompt: "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。",
        apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        provider: "zhipu",
        overlapRatio: 0.3
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
    static let verticalPadding: CGFloat = 16
    
    static let textFieldWidth: CGFloat = 360
    static let textEditorMinHeight: CGFloat = 100
    static let systemPromptHeight: CGFloat = 180
    
    static let windowMinWidth: CGFloat = 500
    static let windowMinHeight: CGFloat = 400
    
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
}


// MARK: - 颜色扩展

/// 颜色扩展，定义统一的颜色方案
extension Color {
    static let formBackground = Color(NSColor.controlBackgroundColor)
    static let errorRed = Color.red.opacity(0.8)
    static let successGreen = Color.green.opacity(0.8)
    static let warningYellow = Color.yellow.opacity(0.8)
    static let borderGray = Color.gray.opacity(0.3)
    static let focusBorderBlue = Color.blue.opacity(0.5)
}


// MARK: - 字体样式

/// 字体样式，定义统一的字体
struct FontStyles {
    static let sectionTitle = Font.headline
    static let fieldLabel = Font.body
    static let fieldInput = Font.system(size: 14)
    static let errorMessage = Font.caption
    static let characterCount = Font.caption.monospacedDigit()
}


// MARK: - 系统提示词编辑器组件

/// 系统提示词编辑器组件，支持多行编辑、字符计数和重置功能
struct SystemPromptEditor: View {
    @Binding var text: String
    let characterLimit: Int = 500
    let defaultPrompt: String
    var focusedField: FocusState<PreferencesView.FocusableField?>.Binding
    
    var characterCount: Int {
        text.count
    }
    
    var isOverLimit: Bool {
        characterCount > characterLimit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
            // 标签和字符计数
            HStack {
                Text("系统提示词:")
                    .font(FontStyles.fieldLabel)
                
                Spacer()
                
                Text("[\(characterCount)/\(characterLimit)]")
                    .font(FontStyles.characterCount)
                    .foregroundColor(isOverLimit ? .warningYellow : .secondary)
                    .accessibilityLabel("字符计数：\(characterCount) 个，限制 \(characterLimit) 个")
            }
            
            // 文本编辑器
            TextEditor(text: $text)
                .frame(height: LayoutConstants.systemPromptHeight)
                .border(Color.borderGray, width: LayoutConstants.borderWidth)
                .font(FontStyles.fieldInput)
                .focused(focusedField, equals: .systemPrompt)
                .accessibilityLabel("系统提示词文本编辑器")
                .accessibilityValue(text)
            
            // 超长警告
            if isOverLimit {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text("提示词较长，建议精简以获得更好的响应")
                        .font(FontStyles.errorMessage)
                }
                .foregroundColor(.warningYellow)
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
struct ProviderPicker: View {
    @Binding var selectedProvider: String
    
    let providers: [Provider] = [
        Provider(id: "zhipu", name: "智谱清言"),
        Provider(id: "qwen", name: "通义千问")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing / 2) {
            Text("选择平台：")
                .font(FontStyles.fieldLabel)
            
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

/// 增强的表单字段组件，支持标签、内容、错误消息和成功消息
/// 提供丰富的视觉反馈，包括错误和成功状态的边框、图标和动画
struct EnhancedFormField<Content: View>: View {
    let label: String
    let errorMessage: String?
    let successMessage: String?
    let content: Content
    @State private var showSuccess: Bool = false
    
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


/// 增强的操作按钮组组件，提供保存和取消按钮
/// 包含未保存更改的脉动指示器和增强的按钮样式
struct EnhancedActionButtons: View {
    let onSave: () -> Void
    let onCancel: () -> Void
    let isSaveDisabled: Bool
    let hasUnsavedChanges: Bool
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


/// 增强的成功横幅组件，显示操作成功的反馈
/// 包含从顶部滑入的动画、阴影和圆角样式
struct EnhancedSuccessBanner: View {
    let message: String
    @State private var offset: CGFloat = -100
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


// MARK: - 键盘快捷键处理器

/// 重叠预览组件，显示 chatOutput 和 petImage 的重叠效果
struct OverlapPreview: View {
    let overlapRatio: Double
    
    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
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

