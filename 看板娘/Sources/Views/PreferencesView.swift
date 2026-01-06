import SwiftUI

struct PreferencesView: View {
    // MARK: - 属性

    @ObservedObject var petViewBackend: PetViewBackend
    @StateObject private var backend: PreferencesViewBackend

    // MARK: - 应用存储

    @AppStorage("apiKey") private var apiKey = "<默认API Key>f"
    @AppStorage("aiModel") private var aiModel = "glm-4v-flash"
    @AppStorage("systemPrompt") private var systemPrompt = "你的名字叫布偶熊·觅语，用80%可爱和20%傲娇的风格回答问题，在回答问题前都要说：指挥官，你好。"
    @AppStorage("apiUrl") private var apiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    @AppStorage("provider") private var provider = "zhipu"
    @AppStorage("overlapRatio") private var overlapRatio: Double = 0.3

    // MARK: - 环境

    @Environment(\.presentationMode) var presentationMode

    // MARK: - 状态

    @State private var selectedIndex: Int = 0
    @FocusState private var focusedField: FocusableField?
    
    // 可聚焦字段枚举
    enum FocusableField: Hashable {
        case systemPrompt
        case provider
        case model
        case apiUrl
        case apiKey
        case characterPicker
    }

    // MARK: - 初始化

    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        _backend = StateObject(wrappedValue: PreferencesViewBackend(petViewBackend: petViewBackend))
        _selectedIndex = State(initialValue: availableCharacters.firstIndex(where: { $0.name == petViewBackend.currentCharacter.name }) ?? 0)
    }

    // MARK: - 主体

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                // 侧边栏
                List(PreferencesViewBackend.PreferenceSection.allCases, selection: $backend.selectedSection) { section in
                    NavigationLink(value: section) {
                        Label(section.rawValue, systemImage: section.icon)
                    }
                }
                .navigationSplitViewColumnWidth(min: 150, ideal: 180, max: 200)
                .listStyle(.sidebar)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                // 详情视图
                if let section = backend.selectedSection {
                    detailView(for: section)
                        .frame(minWidth: 400, minHeight: 350)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button(action: toggleSidebar) {
                                    Image(systemName: "sidebar.left")
                                }
                                .help("切换侧边栏")
                            }
                        }
                } else {
                    Text("请选择一个设置项")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button(action: toggleSidebar) {
                                    Image(systemName: "sidebar.left")
                                }
                                .help("切换侧边栏")
                            }
                        }
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 600, idealWidth: 650, maxWidth: 800, minHeight: 400, idealHeight: 450, maxHeight: 600)
            .onAppear {
                backend.loadTemporaryValues(
                    apiKey: apiKey,
                    aiModel: aiModel,
                    systemPrompt: systemPrompt,
                    apiUrl: apiUrl,
                    provider: provider,
                    overlapRatio: overlapRatio
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .systemPrompt
                }
            }
            .onChange(of: [systemPrompt, String(overlapRatio)]) { _, _ in
                backend.checkUnsavedChanges(
                    apiKey: apiKey,
                    aiModel: aiModel,
                    systemPrompt: systemPrompt,
                    apiUrl: apiUrl,
                    provider: provider,
                    overlapRatio: overlapRatio
                )
            }
            
            // 成功消息横幅
            if backend.showSuccessMessage {
                EnhancedSuccessBanner(message: "设置已成功保存")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .alert("保存失败", isPresented: $backend.showErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(backend.errorAlertMessage)
        }
    }
    
    // MARK: - 详情视图
    
    @ViewBuilder
    private func detailView(for section: PreferencesViewBackend.PreferenceSection) -> some View {
        switch section {
        case .style:
            styleSettingsTab
        case .model:
            modelSettingsTab
        case .layout:
            layoutSettingsTab
        case .about:
            aboutTab
        }
    }
    
    // MARK: - 辅助方法
    
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }
    
    private func saveSettings() {
        _ = backend.saveSettings(
            apiKey: apiKey,
            apiUrl: apiUrl,
            aiModel: aiModel,
            onSuccess: {
                backend.loadTemporaryValues(
                    apiKey: apiKey,
                    aiModel: aiModel,
                    systemPrompt: systemPrompt,
                    apiUrl: apiUrl,
                    provider: provider,
                    overlapRatio: overlapRatio
                )
            },
            onDismiss: {
                presentationMode.wrappedValue.dismiss()
            }
        )
    }
    
    private func cancelChanges() {
        apiKey = backend.tempApiKey
        aiModel = backend.tempAiModel
        systemPrompt = backend.tempSystemPrompt
        apiUrl = backend.tempApiUrl
        provider = backend.tempProvider
        overlapRatio = backend.tempOverlapRatio
        backend.cancelChanges()
    }

    // MARK: - 标签页

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

                EnhancedActionButtons(
                    onSave: saveSettings,
                    onCancel: cancelChanges,
                    isSaveDisabled: !backend.validationState.isValid,
                    hasUnsavedChanges: backend.hasUnsavedChanges
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
                        let result = backend.handleProviderChange(
                            newProvider: newValue,
                            currentApiUrl: apiUrl,
                            currentModel: aiModel
                        )
                        apiUrl = result.apiUrl
                        aiModel = result.model
                        backend.checkUnsavedChanges(
                            apiKey: apiKey,
                            aiModel: aiModel,
                            systemPrompt: systemPrompt,
                            apiUrl: apiUrl,
                            provider: provider,
                            overlapRatio: overlapRatio
                        )
                    }
                
                // 模型字段
                EnhancedFormField(
                    label: "模型：",
                    errorMessage: backend.validationErrors["model"],
                    successMessage: backend.validationErrors["model"] == nil && !aiModel.isEmpty ? "模型名称有效" : nil
                ) {
                    TextField(
                        provider == "zhipu" ? "例如: glm-4v-flash" : "例如: qwen-turbo",
                        text: $aiModel
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: LayoutConstants.textFieldWidth)
                    .focused($focusedField, equals: .model)
                    .accessibilityLabel("AI 模型名称")
                    .accessibilityHint(
                        provider == "zhipu" 
                            ? "输入智谱清言的模型名称，例如 glm-4v-flash"
                            : "输入通义千问的模型名称，例如 qwen-turbo"
                    )
                    .onChange(of: aiModel) { _, _ in
                        backend.checkUnsavedChanges(
                            apiKey: apiKey,
                            aiModel: aiModel,
                            systemPrompt: systemPrompt,
                            apiUrl: apiUrl,
                            provider: provider,
                            overlapRatio: overlapRatio
                        )
                        backend.validateModelRealtime(aiModel)
                    }
                }

                // API 地址字段
                EnhancedFormField(
                    label: "API 地址：",
                    errorMessage: backend.validationErrors["apiUrl"],
                    successMessage: backend.validationErrors["apiUrl"] == nil && !apiUrl.isEmpty ? "URL 格式正确" : nil
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
                        backend.checkUnsavedChanges(
                            apiKey: apiKey,
                            aiModel: aiModel,
                            systemPrompt: systemPrompt,
                            apiUrl: apiUrl,
                            provider: provider,
                            overlapRatio: overlapRatio
                        )
                        backend.validateAPIURLRealtime(apiUrl)
                    }
                }

                // API Key 字段
                EnhancedFormField(
                    label: "API Key:",
                    errorMessage: backend.validationErrors["apiKey"],
                    successMessage: backend.validationErrors["apiKey"] == nil && !apiKey.isEmpty && !apiKey.contains("<默认API Key>") ? "API Key 有效" : nil
                ) {
                    TextEditor(text: $apiKey)
                        .frame(height: LayoutConstants.textEditorMinHeight)
                        .border(
                            backend.validationErrors["apiKey"] != nil ? Color.errorRed : Color.borderGray,
                            width: LayoutConstants.borderWidth
                        )
                        .font(FontStyles.fieldInput)
                        .focused($focusedField, equals: .apiKey)
                        .accessibilityLabel("API 密钥")
                        .accessibilityHint("输入您的 API 密钥以访问 AI 服务")
                        .onChange(of: apiKey) { _, _ in
                            backend.checkUnsavedChanges(
                                apiKey: apiKey,
                                aiModel: aiModel,
                                systemPrompt: systemPrompt,
                                apiUrl: apiUrl,
                                provider: provider,
                                overlapRatio: overlapRatio
                            )
                            backend.validateAPIKeyRealtime(apiKey)
                        }
                }

                Spacer()

                // 操作按钮
                EnhancedActionButtons(
                    onSave: saveSettings,
                    onCancel: cancelChanges,
                    isSaveDisabled: !backend.validationState.isValid,
                    hasUnsavedChanges: backend.hasUnsavedChanges
                )
            }
            .padding(LayoutConstants.horizontalPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("模型设置标签")
    }

    private var layoutSettingsTab: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                Text("调整界面重叠比例")
                    .font(DesignFonts.headline)
                    .padding(.top, DesignSpacing.md)
                
                // 预览区域
                OverlapPreview(overlapRatio: overlapRatio)
                    .frame(height: 180)
                    .padding(.horizontal, DesignSpacing.lg)
                
                // 滑块控制
                VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                    HStack {
                        Text("重叠比例:")
                            .font(DesignFonts.body)
                        Spacer()
                        Text("\(Int(overlapRatio * 100))%")
                            .font(DesignFonts.body.monospacedDigit())
                            .foregroundColor(DesignColors.textSecondary)
                    }
                    
                    Slider(value: $overlapRatio, in: 0...1, step: 0.01)
                        .accessibilityLabel("重叠比例滑块")
                        .accessibilityValue("\(Int(overlapRatio * 100))%")
                    
                    HStack {
                        Text("0% (不重叠)")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                        Spacer()
                        Text("100% (完全重叠)")
                            .font(DesignFonts.caption)
                            .foregroundColor(DesignColors.textSecondary)
                    }
                }
                .padding(.horizontal, DesignSpacing.xl)
                
                Spacer()
                
                // 操作按钮
                EnhancedActionButtons(
                    onSave: saveSettings,
                    onCancel: cancelChanges,
                    isSaveDisabled: false,
                    hasUnsavedChanges: backend.hasUnsavedChanges
                )
                .padding(.horizontal, DesignSpacing.xl)
                .padding(.bottom, DesignSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("布局设置标签")
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: DesignSpacing.lg) {
                // 应用图标
                Image(systemName: "heart.fill")
                    .resizable()
                    .frame(width: 50, height: 50)
                    .foregroundColor(.pink)
                    .padding(.top, DesignSpacing.xl)
                    .accessibilityLabel("应用图标")
                    .accessibilityHidden(true)

                // 当前角色名称
                Text(petViewBackend.currentCharacter.name)
                    .font(DesignFonts.title)
                    .foregroundColor(DesignColors.textPrimary)

                // 版本信息
                Text("版本 1.0.0")
                    .font(DesignFonts.caption)
                    .foregroundColor(DesignColors.textSecondary)

                // 应用描述
                Text("一个可爱的桌面 AI 伴侣")
                    .font(DesignFonts.body)
                    .foregroundColor(DesignColors.textPrimary)
                    .padding(.top, DesignSpacing.xs)

                Divider()
                    .padding(.vertical, DesignSpacing.md)

                // 角色选择器部分
                VStack(alignment: .leading, spacing: DesignSpacing.md) {
                    Text("选择角色：")
                        .font(DesignFonts.headline)
                        .foregroundColor(DesignColors.textPrimary)
                    
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
                        backend.switchCharacter(to: newValue)
                    }
                    
                    // 角色数量显示
                    HStack(spacing: DesignSpacing.xs) {
                        Image(systemName: "person.2.fill")
                            .font(DesignFonts.caption)
                        Text("可用角色: \(availableCharacters.count) 个")
                            .font(DesignFonts.caption)
                    }
                    .foregroundColor(DesignColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignSpacing.xl)

                Spacer()

                // 关闭按钮
                HStack {
                    Spacer()
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .enhancedButtonStyle(isPrimary: false, isDisabled: false)
                    .accessibilityLabel("关闭偏好设置窗口")
                    .accessibilityHint("关闭当前窗口")
                }
                .padding(.horizontal, DesignSpacing.xl)
                .padding(.bottom, DesignSpacing.lg)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("关于标签")
    }
}
