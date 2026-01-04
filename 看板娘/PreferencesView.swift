import SwiftUI

struct PreferencesView: View {
    // MARK: - Properties

    @ObservedObject var backend: PetViewBackend

    // MARK: - AppStorage

    @AppStorage("apiKey") private var apiKey = "<默认API Key>f"
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    @AppStorage("provider") private var provider = "zhipu"

    // MARK: - Environment

    @Environment(\.presentationMode) var presentationMode

    // MARK: - State

    @State private var selectedIndex: Int = 0
    
    // Validation state
    @State private var validationErrors: [String: String] = [:]
    @State private var validationState = ValidationState()
    
    // UI feedback state
    @State private var showSuccessMessage: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorAlertMessage: String = ""
    @State private var hasUnsavedChanges: Bool = false
    
    // Temporary storage for cancel operation
    @State private var tempApiKey: String = ""
    @State private var tempAiModel: String = ""
    @State private var tempSystemPrompt: String = ""
    @State private var tempApiUrl: String = ""
    @State private var tempProvider: String = ""
    
    // Focus state for keyboard navigation
    @FocusState private var focusedField: FocusableField?
    
    // Enum for focusable fields
    enum FocusableField: Hashable {
        case systemPrompt
        case provider
        case model
        case apiUrl
        case apiKey
        case characterPicker
    }

    // MARK: - Init

    init(backend: PetViewBackend) {
        self.backend = backend
        if let index = availableCharacters.firstIndex(where: { $0.name == backend.currentCharacter.name }) {
            _selectedIndex = State(initialValue: index)
        }
        
        // Load temporary values for cancel operation
        // Note: We can't access @AppStorage in init, so we'll load in onAppear
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                styleSettingsTab
                    .tabItem { Label("风格", systemImage: "person.crop.circle") }

                modelSettingsTab
                    .tabItem { Label("模型设置", systemImage: "network") }

                aboutTab
                    .tabItem { Label("关于", systemImage: "info.circle") }
            }
            .frame(width: 400, height: 350)
            .onAppear {
                loadTemporaryValues()
                // Set initial focus to system prompt field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .systemPrompt
                }
            }
            .onChange(of: systemPrompt) { _, _ in
                updateUnsavedChangesFlag()
            }
            
            // 成功消息横幅
            if showSuccessMessage {
                SuccessBanner(message: "设置已成功保存")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        // 键盘快捷键支持
        .background(KeyboardShortcutHandler(
            onSave: { _ = saveSettings() },
            onCancel: cancelChanges,
            onClose: { presentationMode.wrappedValue.dismiss() }
        ))
        .alert("保存失败", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorAlertMessage)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Update unsaved changes flag by comparing current values with temporary storage
    private func updateUnsavedChangesFlag() {
        hasUnsavedChanges = apiKey != tempApiKey ||
                           aiModel != tempAiModel ||
                           systemPrompt != tempSystemPrompt ||
                           apiUrl != tempApiUrl ||
                           provider != tempProvider
    }
    
    /// Load current values into temporary storage for cancel operation
    private func loadTemporaryValues() {
        tempApiKey = apiKey
        tempAiModel = aiModel
        tempSystemPrompt = systemPrompt
        tempApiUrl = apiUrl
        tempProvider = provider
    }
    
    /// Restore values from temporary storage (cancel operation)
    private func restoreFromTemporary() {
        apiKey = tempApiKey
        aiModel = tempAiModel
        systemPrompt = tempSystemPrompt
        apiUrl = tempApiUrl
        provider = tempProvider
        hasUnsavedChanges = false
    }
    
    /// Validate all input fields
    private func validateAllFields() -> Bool {
        validationState.clearErrors()
        
        let apiKeyValid = validationState.validateAPIKey(apiKey)
        let apiUrlValid = validationState.validateAPIURL(apiUrl)
        let modelValid = validationState.validateModel(aiModel)
        
        // Update validation errors dictionary
        validationErrors.removeAll()
        if let error = validationState.apiKeyError {
            validationErrors["apiKey"] = error
        }
        if let error = validationState.apiUrlError {
            validationErrors["apiUrl"] = error
        }
        if let error = validationState.modelError {
            validationErrors["model"] = error
        }
        
        return apiKeyValid && apiUrlValid && modelValid
    }
    
    /// Save settings with validation
    @discardableResult
    private func saveSettings() -> Bool {
        // Validate all fields
        guard validateAllFields() else {
            // Show error alert with validation errors
            let errors = validationErrors.values.joined(separator: "\n")
            errorAlertMessage = "请修正以下错误：\n\n\(errors)"
            showErrorAlert = true
            return false
        }
        
        // Update temporary values to match saved values
        loadTemporaryValues()
        
        // Post notification that settings changed
        NotificationCenter.default.post(
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
        
        // Show success message with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            showSuccessMessage = true
        }
        hasUnsavedChanges = false
        
        // Hide success message after 2 seconds and close window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showSuccessMessage = false
            }
            // Close window after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                presentationMode.wrappedValue.dismiss()
            }
        }
        
        return true
    }
    
    /// Cancel changes and restore original values
    private func cancelChanges() {
        restoreFromTemporary()
        validationErrors.removeAll()
        validationState.clearErrors()
    }

    // MARK: - Tabs

    private var styleSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                SystemPromptEditor(
                    text: $systemPrompt,
                    defaultPrompt: PreferencesData.default.systemPrompt,
                    focusedField: $focusedField
                )
                .accessibilityLabel("系统提示词编辑器")
                .accessibilityHint("编辑 AI 角色的个性和行为设置")

                Spacer()

                ActionButtons(
                    onSave: { _ = saveSettings() },
                    onCancel: cancelChanges,
                    isSaveDisabled: !validationState.isValid,
                    hasUnsavedChanges: hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("风格设置标签")
    }

    private var modelSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutConstants.sectionSpacing) {
                // 提供商选择器
                ProviderPicker(selectedProvider: $provider)
                    .accessibilityLabel("AI 服务提供商选择器")
                    .accessibilityHint("选择智谱清言或通义千问作为 AI 服务提供商")
                    .focused($focusedField, equals: .provider)
                    .onChange(of: provider) { _, newValue in
                        // 提供商切换逻辑：更新默认 URL 和模型
                        if newValue == "zhipu" {
                            if apiUrl.contains("qwen") || apiUrl.isEmpty {
                                apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
                            }
                            if aiModel.isEmpty || aiModel.contains("qwen") {
                                aiModel = "glm-4v-flash"
                            }
                        } else if newValue == "qwen" {
                            if apiUrl.contains("bigmodel") || apiUrl.isEmpty {
                                apiUrl = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
                            }
                            if aiModel.isEmpty || aiModel.contains("glm") {
                                aiModel = "qwen-turbo"
                            }
                        }
                        updateUnsavedChangesFlag()
                    }
                
                // 模型字段 - 仅对智谱清言显示
                if provider == "zhipu" {
                    FormField(
                        label: "模型：",
                        errorMessage: validationErrors["model"]
                    ) {
                        TextField("例如: glm-4v-flash", text: $aiModel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: LayoutConstants.textFieldWidth)
                            .focused($focusedField, equals: .model)
                            .accessibilityLabel("AI 模型名称")
                            .accessibilityHint("输入智谱清言的模型名称，例如 glm-4v-flash")
                            .onChange(of: aiModel) { _, _ in
                                updateUnsavedChangesFlag()
                                // 实时验证
                                validationState.validateModel(aiModel)
                                if let error = validationState.modelError {
                                    validationErrors["model"] = error
                                } else {
                                    validationErrors.removeValue(forKey: "model")
                                }
                            }
                    }
                }
                
                // 通义千问特定配置提示
                if provider == "qwen" {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                        Text("通义千问使用默认模型配置")
                            .font(FontStyles.errorMessage)
                    }
                    .foregroundColor(.blue.opacity(0.8))
                }

                // API 地址字段
                FormField(
                    label: "API 地址：",
                    errorMessage: validationErrors["apiUrl"]
                ) {
                    TextField(
                        provider == "zhipu" 
                            ? "例如: https://open.bigmodel.cn/api/paas/v4/..." 
                            : "例如: https://dashscope.aliyuncs.com/api/v1/...",
                        text: $apiUrl
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: LayoutConstants.textFieldWidth)
                    .focused($focusedField, equals: .apiUrl)
                    .accessibilityLabel("API 服务地址")
                    .accessibilityHint("输入 AI 服务的 API 地址，必须是 HTTPS 协议")
                    .onChange(of: apiUrl) { _, _ in
                        updateUnsavedChangesFlag()
                        // 实时验证
                        validationState.validateAPIURL(apiUrl)
                        if let error = validationState.apiUrlError {
                            validationErrors["apiUrl"] = error
                        } else {
                            validationErrors.removeValue(forKey: "apiUrl")
                        }
                    }
                }
                
                // 验证成功提示
                if validationErrors["apiUrl"] == nil && !apiUrl.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("URL 格式正确")
                            .font(FontStyles.errorMessage)
                    }
                    .foregroundColor(.successGreen)
                }

                // API Key 字段
                FormField(
                    label: "API Key:",
                    errorMessage: validationErrors["apiKey"]
                ) {
                    TextEditor(text: $apiKey)
                        .frame(height: LayoutConstants.textEditorMinHeight)
                        .border(
                            validationErrors["apiKey"] != nil ? Color.errorRed : Color.borderGray,
                            width: LayoutConstants.borderWidth
                        )
                        .font(FontStyles.fieldInput)
                        .focused($focusedField, equals: .apiKey)
                        .accessibilityLabel("API 密钥")
                        .accessibilityHint("输入您的 API 密钥以访问 AI 服务")
                        .onChange(of: apiKey) { _, _ in
                            updateUnsavedChangesFlag()
                            // 实时验证
                            validationState.validateAPIKey(apiKey)
                            if let error = validationState.apiKeyError {
                                validationErrors["apiKey"] = error
                            } else {
                                validationErrors.removeValue(forKey: "apiKey")
                            }
                        }
                }

                Spacer()

                // 操作按钮
                ActionButtons(
                    onSave: { _ = saveSettings() },
                    onCancel: cancelChanges,
                    isSaveDisabled: !validationState.isValid,
                    hasUnsavedChanges: hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("模型设置标签")
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: LayoutConstants.sectionSpacing) {
                // 应用图标
                Image(systemName: "heart.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.pink)
                    .padding(.top, LayoutConstants.verticalPadding)
                    .accessibilityLabel("应用图标")
                    .accessibilityHidden(true)

                // 当前角色名称
                Text(backend.currentCharacter.name)
                    .font(.title)
                    .bold()

                // 版本信息
                Text("版本 1.0.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 应用描述
                Text("一个可爱的桌面 AI 伴侣")
                    .font(.body)
                    .padding(.top, 5)

                Divider()
                    .padding(.vertical, LayoutConstants.fieldSpacing)

                // 角色选择器部分
                VStack(alignment: .leading, spacing: LayoutConstants.fieldSpacing) {
                    Text("选择角色：")
                        .font(FontStyles.fieldLabel)
                    
                    Picker("选择角色", selection: $selectedIndex) {
                        ForEach(0..<availableCharacters.count, id: \.self) { index in
                            Text(availableCharacters[index].name)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .focused($focusedField, equals: .characterPicker)
                    .accessibilityLabel("角色选择器")
                    .accessibilityHint("选择不同的桌面宠物角色")
                    .onChange(of: selectedIndex) { _, newValue in
                        let newCharacter = availableCharacters[newValue]
                        backend.switchToCharacter(newCharacter)
                    }
                    
                    // 角色数量显示
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                        Text("可用角色: \(availableCharacters.count) 个")
                            .font(FontStyles.errorMessage)
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LayoutConstants.horizontalPadding)

                Spacer()

                // 关闭按钮
                HStack {
                    Spacer()
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .accessibilityLabel("关闭偏好设置窗口")
                    .accessibilityHint("关闭当前窗口")
                }
                .padding(.horizontal, LayoutConstants.horizontalPadding)
                .padding(.bottom, LayoutConstants.verticalPadding)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("关于标签")
    }
}
