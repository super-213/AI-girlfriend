import Foundation
import SwiftUI
import AppKit

// MARK: - ValidationError

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


// MARK: - PreferencesData

/// 偏好设置数据结构体，封装所有设置数据
struct PreferencesData: Equatable {
    var apiKey: String
    var aiModel: String
    var systemPrompt: String
    var apiUrl: String
    var provider: String
    
    static let `default` = PreferencesData(
        apiKey: "",
        aiModel: "glm-4v-flash",
        systemPrompt: "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。",
        apiUrl: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        provider: "zhipu"
    )
}


// MARK: - ValidationState

/// 验证状态结构体，管理所有字段的验证逻辑
struct ValidationState {
    var apiKeyError: String?
    var apiUrlError: String?
    var modelError: String?
    
    /// 检查所有字段是否有效
    var isValid: Bool {
        apiKeyError == nil && apiUrlError == nil && modelError == nil
    }
    
    /// 验证 API 密钥
    /// - Parameter key: API 密钥字符串
    /// - Returns: 验证是否通过
    @discardableResult
    mutating func validateAPIKey(_ key: String) -> Bool {
        // 检查是否为空
        guard !key.isEmpty else {
            apiKeyError = ValidationError.emptyAPIKey.errorDescription
            return false
        }
        
        // 检查是否为默认占位符
        guard !key.contains("<默认API Key>") && !key.hasSuffix("f") else {
            apiKeyError = ValidationError.invalidAPIKey.errorDescription
            return false
        }
        
        // 检查最小长度（通常 API 密钥至少 20 个字符）
        guard key.count >= 20 else {
            apiKeyError = ValidationError.invalidAPIKey.errorDescription
            return false
        }
        
        apiKeyError = nil
        return true
    }

    
    /// 验证 API URL
    /// - Parameter urlString: URL 字符串
    /// - Returns: 验证是否通过
    @discardableResult
    mutating func validateAPIURL(_ urlString: String) -> Bool {
        // 检查是否为空
        guard !urlString.isEmpty else {
            apiUrlError = ValidationError.invalidURL.errorDescription
            return false
        }
        
        // 检查 URL 格式
        guard let url = URL(string: urlString) else {
            apiUrlError = ValidationError.invalidURL.errorDescription
            return false
        }
        
        // 检查是否为 HTTPS
        guard url.scheme == "https" else {
            apiUrlError = ValidationError.invalidURL.errorDescription
            return false
        }
        
        // 检查是否有主机名
        guard url.host != nil else {
            apiUrlError = ValidationError.invalidURL.errorDescription
            return false
        }
        
        apiUrlError = nil
        return true
    }

    
    /// 验证模型名称
    /// - Parameter model: 模型名称字符串
    /// - Returns: 验证是否通过
    @discardableResult
    mutating func validateModel(_ model: String) -> Bool {
        // 检查是否为空
        guard !model.isEmpty else {
            modelError = ValidationError.emptyModel.errorDescription
            return false
        }
        
        // 检查是否包含有效字符（字母、数字、连字符、下划线）
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


// MARK: - LayoutConstants

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


// MARK: - Color Extensions

/// 颜色扩展，定义统一的颜色方案
extension Color {
    static let formBackground = Color(NSColor.controlBackgroundColor)
    static let errorRed = Color.red.opacity(0.8)
    static let successGreen = Color.green.opacity(0.8)
    static let warningYellow = Color.yellow.opacity(0.8)
    static let borderGray = Color.gray.opacity(0.3)
    static let focusBorderBlue = Color.blue.opacity(0.5)
}


// MARK: - Font Styles

/// 字体样式，定义统一的字体
struct FontStyles {
    static let sectionTitle = Font.headline
    static let fieldLabel = Font.body
    static let fieldInput = Font.system(size: 14)
    static let errorMessage = Font.caption
    static let characterCount = Font.caption.monospacedDigit()
}


// MARK: - FormField Component

/// 可重用的表单字段组件，提供一致的布局和错误显示
struct FormField<Content: View>: View {
    let label: String
    let errorMessage: String?
    let content: Content
    
    init(
        label: String,
        errorMessage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.errorMessage = errorMessage
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing / 2) {
            Text(label)
                .font(FontStyles.fieldLabel)
            
            content
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutConstants.cornerRadius)
                        .stroke(errorMessage != nil ? Color.errorRed : Color.clear, lineWidth: LayoutConstants.borderWidth)
                )
            
            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(FontStyles.errorMessage)
                }
                .foregroundColor(.errorRed)
            }
        }
    }
}


// MARK: - SystemPromptEditor Component

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


// MARK: - Provider Model

/// 服务提供商数据模型
struct Provider: Identifiable {
    let id: String
    let name: String
}


// MARK: - ProviderPicker Component

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


// MARK: - ActionButtons Component

/// 操作按钮组组件，提供保存和取消按钮
struct ActionButtons: View {
    let onSave: () -> Void
    let onCancel: () -> Void
    let isSaveDisabled: Bool
    let hasUnsavedChanges: Bool
    
    var body: some View {
        HStack(spacing: LayoutConstants.fieldSpacing) {
            // 未保存更改指示器
            if hasUnsavedChanges {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.orange)
                    Text("未保存的更改")
                        .font(FontStyles.errorMessage)
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("有未保存的更改")
            }
            
            Spacer()
            
            Button("取消") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("取消更改")
            .accessibilityHint("放弃所有未保存的更改并恢复原值")
            
            Button("保存") {
                onSave()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaveDisabled)
            .accessibilityLabel("保存设置")
            .accessibilityHint(isSaveDisabled ? "保存按钮已禁用，请修正验证错误" : "保存所有更改并关闭窗口")
        }
    }
}


// MARK: - SuccessBanner Component

/// 成功消息横幅组件，显示操作成功的反馈
struct SuccessBanner: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.white)
            Text(message)
                .foregroundColor(.white)
                .font(FontStyles.fieldLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.successGreen)
        .cornerRadius(LayoutConstants.cornerRadius)
        .shadow(radius: 4)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("成功：\(message)")
    }
}


// MARK: - KeyboardShortcutHandler

/// 键盘快捷键处理器，提供全局键盘快捷键支持
struct KeyboardShortcutHandler: NSViewRepresentable {
    let onSave: () -> Void
    let onCancel: () -> Void
    let onClose: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyEventHandlingView()
        view.onSave = onSave
        view.onCancel = onCancel
        view.onClose = onClose
        
        // 确保视图可以接收键盘事件
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyEventHandlingView {
            view.onSave = onSave
            view.onCancel = onCancel
            view.onClose = onClose
        }
    }
    
    class KeyEventHandlingView: NSView {
        var onSave: (() -> Void)?
        var onCancel: (() -> Void)?
        var onClose: (() -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            // ⌘S - 保存
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
                onSave?()
                return
            }
            
            // ⌘W - 关闭
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "w" {
                onClose?()
                return
            }
            
            // Escape - 取消
            if event.keyCode == 53 { // Escape key code
                onCancel?()
                return
            }
            
            super.keyDown(with: event)
        }
    }
}
