//
//  PreferencesViewBackend.swift
//  桌面宠物应用
//
//  偏好设置视图的业务逻辑和状态管理
//

import Foundation
import SwiftUI
import Combine

// MARK: - 偏好设置视图后端

/// 偏好设置视图的后端逻辑控制器
/// 负责管理设置验证、角色绑定和数据持久化
class PreferencesViewBackend: ObservableObject {
    private static let currentAgentTemplateVersion = 2
    // MARK: - 属性
    
    /// 当前选中的设置分区
    @Published var selectedSection: PreferenceSection? = .style
    
    /// 是否显示成功消息
    @Published var showSuccessMessage: Bool = false
    
    /// 是否显示错误警告
    @Published var showErrorAlert: Bool = false
    
    /// 错误警告消息内容
    @Published var errorAlertMessage: String = ""
    
    /// 是否有未保存的更改
    @Published var hasUnsavedChanges: Bool = false
    
    /// 静态提示词列表
    @Published var staticMessages: [String] = []
    
    // 角色绑定相关
    
    /// 自定义角色列表
    @Published var customCharacters: [PetCharacter] = []
    
    /// 是否显示导入错误
    @Published var showImportError: Bool = false
    
    /// 导入错误消息
    @Published var importErrorMessage: String = ""

    // MARK: - Agent/Skill 文件管理
    
    /// 当前 agent.md 文件
    @Published var agentFile: AgentFile? = nil
    
    /// 已添加的 skill.md 文件列表
    @Published var skillFiles: [SkillFile] = []
    
    /// 技能文件操作错误提示
    @Published var showSkillFileError: Bool = false
    
    /// 技能文件操作错误信息
    @Published var skillFileErrorMessage: String = ""
    
    // MARK: - 取消操作的临时存储
    
    /// 临时存储的设置数据（用于取消操作）
    private var tempData: PreferencesData = .default
    
    // MARK: - 依赖项
    
    /// 宠物视图后端的引用
    private let petViewBackend: PetViewBackend

    /// 稳定机器控制服务
    private let controlService = PetControlService.shared
    
    // MARK: - 初始化
    
    /// 初始化偏好设置后端
    /// - Parameter petViewBackend: 宠物视图后端实例
    init(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
        loadCustomCharacters()
        loadStaticMessages()
        loadAgentFile()
        loadSkillFiles()
        upgradeAgentTemplateIfNeeded()
    }
    
    // MARK: - 静态提示词管理
    
    /// 加载静态提示词
    private func loadStaticMessages() {
        if let data = UserDefaults.standard.data(forKey: "staticMessages"),
           let messages = try? JSONDecoder().decode([String].self, from: data) {
            staticMessages = messages
        }
    }
    
    /// 保存静态提示词
    func saveStaticMessages() {
        if let data = try? JSONEncoder().encode(staticMessages) {
            UserDefaults.standard.set(data, forKey: "staticMessages")
        }
    }
    
    // MARK: - 角色绑定方法
    
    /// 加载自定义角色
    private func loadCustomCharacters() {
        if let data = UserDefaults.standard.data(forKey: "customCharacters"),
           let characters = try? JSONDecoder().decode([PetCharacter].self, from: data) {
            customCharacters = characters
        }
    }
    
    /// 保存自定义角色
    /// 保存自定义角色到UserDefaults
    func saveCustomCharacters() {
        if let data = try? JSONEncoder().encode(customCharacters) {
            UserDefaults.standard.set(data, forKey: "customCharacters")
        }
    }
    
    /// 导入GIF文件创建自定义角色
    /// - Parameters:
    ///   - normalGif: 站立状态的GIF文件URL
    ///   - clickGif: 点击动作的GIF文件URL（可选）
    ///   - name: 角色名称
    /// - Returns: 是否导入成功
    func importGIF(normalGif: URL?, clickGif: URL?, name: String) -> Bool {
        guard customCharacters.count < 3 else {
            importErrorMessage = "最多只能保存3个自定义角色"
            showImportError = true
            return false
        }
        
        guard !name.isEmpty else {
            importErrorMessage = "角色名称不能为空"
            showImportError = true
            return false
        }
        
        guard let normalGif = normalGif else {
            importErrorMessage = "必须选择站立GIF"
            showImportError = true
            return false
        }
        
        // 使用Application Support目录存储自定义GIF
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            importErrorMessage = "无法访问应用支持目录"
            showImportError = true
            return false
        }
        
        // 创建应用专属目录
        let appDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "PetApp")
        let animationsURL = appDirectory.appendingPathComponent("CustomAnimations")
        
        do {
            // 确保目录存在
            if !fileManager.fileExists(atPath: animationsURL.path) {
                try fileManager.createDirectory(at: animationsURL, withIntermediateDirectories: true)
            }
            
            let normalFileName = "\(name)_站立.gif"
            let normalDestURL = animationsURL.appendingPathComponent(normalFileName)
            
            // 如果文件已存在，先删除
            if fileManager.fileExists(atPath: normalDestURL.path) {
                try fileManager.removeItem(at: normalDestURL)
            }
            
            try fileManager.copyItem(at: normalGif, to: normalDestURL)
            
            var clickFileName = normalFileName
            if let clickGif = clickGif {
                clickFileName = "\(name)_动作.gif"
                let clickDestURL = animationsURL.appendingPathComponent(clickFileName)
                
                if fileManager.fileExists(atPath: clickDestURL.path) {
                    try fileManager.removeItem(at: clickDestURL)
                }
                
                try fileManager.copyItem(at: clickGif, to: clickDestURL)
            }
            
            // 创建新角色（保存完整路径）
            let newCharacter = PetCharacter(
                name: name,
                normalGif: normalDestURL.path,
                clickGif: clickFileName == normalFileName ? normalDestURL.path : animationsURL.appendingPathComponent(clickFileName).path,
                autoMessages: ["你好，我是\(name)～"]
            )
            
            customCharacters.append(newCharacter)
            saveCustomCharacters()
            
            return true
        } catch {
            importErrorMessage = "导入失败：\(error.localizedDescription)"
            showImportError = true
            return false
        }
    }
    
    /// 删除指定索引的自定义角色
    /// - Parameter index: 要删除的角色索引
    func deleteCustomCharacter(at index: Int) {
        guard index < customCharacters.count else { return }
        
        let character = customCharacters[index]
        let fileManager = FileManager.default
        
        // 删除GIF文件
        let normalURL = URL(fileURLWithPath: character.normalGif)
        let clickURL = URL(fileURLWithPath: character.clickGif)
        
        try? fileManager.removeItem(at: normalURL)
        if character.normalGif != character.clickGif {
            try? fileManager.removeItem(at: clickURL)
        }
        
        customCharacters.remove(at: index)
        saveCustomCharacters()
    }
}

// MARK: - Agent/Skill 文件管理

extension PreferencesViewBackend {
    private func agentSkillsDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "AgentSkills", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法访问应用支持目录"])
        }
        let appDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "PetApp")
        let agentSkillsURL = appDirectory.appendingPathComponent("AgentSkills")
        if !fileManager.fileExists(atPath: agentSkillsURL.path) {
            try fileManager.createDirectory(at: agentSkillsURL, withIntermediateDirectories: true)
        }
        return agentSkillsURL
    }
    
    private func loadAgentFile() {
        guard let data = UserDefaults.standard.data(forKey: AgentSkillStorageKeys.agentFile),
              let saved = try? JSONDecoder().decode(AgentFile.self, from: data) else {
            agentFile = nil
            return
        }
        
        if FileManager.default.fileExists(atPath: saved.path) {
            agentFile = saved
        } else {
            agentFile = nil
            UserDefaults.standard.removeObject(forKey: AgentSkillStorageKeys.agentFile)
        }
    }
    
    private func saveAgentFile() {
        if let agentFile = agentFile, let data = try? JSONEncoder().encode(agentFile) {
            UserDefaults.standard.set(data, forKey: AgentSkillStorageKeys.agentFile)
        } else {
            UserDefaults.standard.removeObject(forKey: AgentSkillStorageKeys.agentFile)
        }
    }
    
    private func loadSkillFiles() {
        guard let data = UserDefaults.standard.data(forKey: AgentSkillStorageKeys.skillFiles),
              let saved = try? JSONDecoder().decode([SkillFile].self, from: data) else {
            skillFiles = []
            return
        }
        
        let fileManager = FileManager.default
        let filtered = saved.filter { fileManager.fileExists(atPath: $0.path) }
        skillFiles = filtered
        
        if filtered.count != saved.count {
            saveSkillFiles()
        }
    }
    
    private func saveSkillFiles() {
        if let data = try? JSONEncoder().encode(skillFiles) {
            UserDefaults.standard.set(data, forKey: AgentSkillStorageKeys.skillFiles)
        }
    }
    
    func importAgentFile(from url: URL) -> Bool {
        do {
            let agentDir = try agentSkillsDirectory()
            let destination = agentDir.appendingPathComponent("agent.md")
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            
            agentFile = AgentFile(
                name: "agent.md",
                path: destination.path,
                updatedAt: Date()
            )
            saveAgentFile()
            return true
        } catch {
            skillFileErrorMessage = "导入 agent.md 失败：\(error.localizedDescription)"
            showSkillFileError = true
            return false
        }
    }
    
    func generateDefaultAgentFile() -> Bool {
        let content = """
        # Agent 指令规范
        
        ## 你的角色
        你是一个智能任务执行助手，可以执行系统命令、调用预置技能、或直接回答问题。
        
        ## 交互模式
        
        你支持三种交互方式：
        
        ### 1. 执行系统命令
        当需要操作文件系统、运行程序时，使用命令格式：
        [命令] ls -la
        
        ### 2. 调用预置技能
        当用户输入包含 "调用 XXX skill" 时，系统会自动加载对应技能说明。
        你根据加载的技能说明执行任务，完成后回复：
        [完成] 任务描述
        
        ### 3. 直接回答
        当问题不需要命令或技能时，直接给出答案，最后标记：
        [完成] 回答内容
        
        ## 输出格式规范
        
        系统命令：[命令] XXX
        任务完成：[完成] XXX
        技能调用：由用户触发（用户输入 "调用 XXX skill"）
        
        ## 严格禁止
        
        - 不要解释你的思考过程
        - 不要添加额外说明或注释
        - 不要使用代码块包裹命令
        - 不要一次性输出多条命令
        - 不要执行危险命令（如 rm -rf /）
        
        ## 工作流程
        
        1. 接收用户输入
        2. 检测是否包含 "调用 XXX skill"
        3. 如有，系统自动加载 skills/XXX/XXX.md 并注入上下文
        4. 根据上下文（Agent.md + skill.md）生成回复
        5. 使用正确格式输出（[命令]/[完成]）

        ## 执行规则
        
        - 需要本地操作时，直接输出：命令: <command>
        - 权限确认由客户端弹窗处理，不要声明“没有权限/无法访问”
        - 只有在命令执行结果明确失败（Permission denied）时才说明权限问题
        - 不要用委婉话术替代命令输出
        
        ## 示例
        
        ### 示例 1：技能调用
        用户：调用 weather skill 查询北京天气
        AI：[完成] 北京今天天气：晴，18°C ~ 26°C，适合户外活动
        
        ### 示例 2：命令执行
        用户：查看当前目录有哪些文件
        AI：命令: ls -la
        用户：[执行完成] ...
        AI：完成: 当前目录共有 5 个文件
        
        ### 示例 3：直接回答
        用户：Python 中如何定义函数？
        AI：完成: 使用 def 关键字：def 函数名 (参数): 缩进代码块
        
        ## 安全原则
        
        - 不执行需要用户交互的命令（如 vi、python 交互模式）
        - 不执行可能破坏系统的命令（如格式化、删除系统文件）
        - 敏感操作前先向用户确认
        - 优先使用只读命令（如 ls、cat、pwd）
        - 命令失败时分析原因并给出替代方案
        
        ## 开始工作
        
        等待用户指令，根据任务类型选择最合适的交互方式。
        """
        
        do {
            let agentDir = try agentSkillsDirectory()
            let destination = agentDir.appendingPathComponent("agent.md")
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try content.write(to: destination, atomically: true, encoding: .utf8)
            
            agentFile = AgentFile(
                name: "agent.md",
                path: destination.path,
                updatedAt: Date()
            )
            saveAgentFile()
            UserDefaults.standard.set(Self.currentAgentTemplateVersion, forKey: AgentSkillStorageKeys.agentTemplateVersion)
            return true
        } catch {
            skillFileErrorMessage = "生成 agent.md 失败：\(error.localizedDescription)"
            showSkillFileError = true
            return false
        }
    }

    private func upgradeAgentTemplateIfNeeded() {
        guard agentFile != nil else { return }
        let storedVersion = UserDefaults.standard.integer(forKey: AgentSkillStorageKeys.agentTemplateVersion)
        if storedVersion < Self.currentAgentTemplateVersion {
            _ = generateDefaultAgentFile()
        }
    }
    
    func removeAgentFile() {
        guard let agentFile = agentFile else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: agentFile.path))
        self.agentFile = nil
        saveAgentFile()
    }
    
    func importSkillFiles(from urls: [URL]) -> Int {
        guard !urls.isEmpty else { return 0 }
        var imported = 0

        for url in urls {
            do {
                let dto = try controlService.importSkill(
                    ImportSkillRequest(
                        filePath: url.path,
                        context: PetControlRequestContext(source: .ui)
                    )
                )
                let newSkill = SkillFile(
                    id: dto.id,
                    name: dto.name,
                    path: dto.path,
                    addedAt: dto.addedAt
                )
                skillFiles.append(newSkill)
                imported += 1
            } catch {
                skillFileErrorMessage = "导入 skill.md 失败：\(error.localizedDescription)"
                showSkillFileError = true
            }
        }

        loadSkillFiles()
        return imported
    }
    
    func deleteSkillFile(at index: Int) {
        guard index < skillFiles.count else { return }
        let skill = skillFiles[index]
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: skill.path))
        skillFiles.remove(at: index)
        saveSkillFiles()
    }
}


// MARK: - 偏好设置分区枚举

/// 偏好设置的分区定义
extension PreferencesViewBackend {
    /// 偏好设置分区枚举
    enum PreferenceSection: String, CaseIterable, Identifiable {
        case style = "风格"
        case model = "模型设置"
        case layout = "布局"
        case skills = "技能"
        case automation = "自动化"
        case characterBinding = "角色绑定"
        case about = "关于"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .style: return "person.crop.circle"
            case .model: return "network"
            case .layout: return "rectangle.stack"
            case .skills: return "hammer.circle"
            case .automation: return "clock.arrow.circlepath"
            case .characterBinding: return "person.2.crop.square.stack"
            case .about: return "info.circle"
            }
        }
    }
}


// MARK: - 临时值管理

/// 临时值管理扩展
extension PreferencesViewBackend {
    /// 加载当前值到临时存储
    func loadTemporaryValues(
        apiKey: String,
        aiModel: String,
        systemPrompt: String,
        apiUrl: String,
        provider: String,
        overlapRatio: Double
    ) {
        tempData = PreferencesData(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio,
            staticMessages: staticMessages
        )
    }
    
    /// 检查是否有未保存的更改
    func checkUnsavedChanges(
        apiKey: String,
        aiModel: String,
        systemPrompt: String,
        apiUrl: String,
        provider: String,
        overlapRatio: Double
    ) {
        let currentData = PreferencesData(
            apiKey: apiKey,
            aiModel: aiModel,
            systemPrompt: systemPrompt,
            apiUrl: apiUrl,
            provider: provider,
            overlapRatio: overlapRatio,
            staticMessages: staticMessages
        )
        hasUnsavedChanges = currentData != tempData
    }
}





// MARK: - 提供商管理

/// 提供商管理扩展
extension PreferencesViewBackend {
    /// 处理提供商切换
    /// - Parameters:
    ///   - newProvider: 新的提供商
    ///   - currentApiUrl: 当前API地址
    ///   - currentModel: 当前模型名称
    /// - Returns: 更新后的API地址和模型名称
    func handleProviderChange(
        newProvider: String,
        currentApiUrl: String,
        currentModel: String
    ) -> (apiUrl: String, model: String) {
        var updatedApiUrl = currentApiUrl
        var updatedModel = currentModel
        
        if newProvider == "zhipu" {
            if currentApiUrl.contains("dashscope") || currentApiUrl.contains("aliyuncs") || currentApiUrl.contains("localhost") || currentApiUrl.isEmpty {
                updatedApiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
            }
            if currentModel.isEmpty || currentModel.contains("qwen") || currentModel.contains("llama") || currentModel.contains("gemma") {
                updatedModel = "glm-4v-flash"
            }
        } else if newProvider == "qwen" {
            if currentApiUrl.contains("bigmodel")
                || currentApiUrl.contains("localhost")
                || currentApiUrl.isEmpty
                || (currentApiUrl.contains("dashscope.aliyuncs.com/compatible-mode/v1")
                    && !currentApiUrl.contains("/chat/completions")) {
                updatedApiUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
            }
            if currentModel.isEmpty || currentModel.contains("glm") || currentModel.contains("llama") || currentModel.contains("gemma") {
                updatedModel = "qwen-plus"
            }
        } else if newProvider == "ollama" {
            if currentApiUrl.contains("bigmodel") || currentApiUrl.contains("dashscope") || currentApiUrl.contains("aliyuncs") || currentApiUrl.isEmpty {
                updatedApiUrl = "http://localhost:11434/api/chat"
            }
            if currentModel.isEmpty || currentModel.contains("glm") || currentModel.contains("qwen-turbo") {
                updatedModel = "qwen2.5"
            }
        }
        
        return (updatedApiUrl, updatedModel)
    }
}


// MARK: - 保存和取消操作

/// 保存和取消操作扩展
extension PreferencesViewBackend {
    /// 保存设置
    /// - Parameters:
    ///   - apiKey: API密钥
    ///   - apiUrl: API地址
    ///   - aiModel: AI模型名称
    ///   - provider: 服务提供商
    ///   - onSuccess: 保存成功回调
    ///   - onDismiss: 关闭窗口回调
    /// - Returns: 是否保存成功
    func saveSettings(
        apiKey: String,
        apiUrl: String,
        aiModel: String,
        provider: String = "zhipu",
        onSuccess: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> Bool {
        // 保存静态提示词
        saveStaticMessages()
        
        // 更新临时值
        onSuccess()
        
        // 发送设置更改通知
        NotificationCenter.default.post(
            name: NSNotification.Name("SettingsChanged"),
            object: nil
        )
        
        // 显示成功消息
        withAnimation(.easeInOut(duration: 0.3)) {
            showSuccessMessage = true
        }
        hasUnsavedChanges = false
        
        // 2秒后隐藏成功消息并关闭窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.showSuccessMessage = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDismiss()
            }
        }
        
        return true
    }
    
    /// 取消更改，恢复到之前的值
    func cancelChanges() {
        hasUnsavedChanges = false
        staticMessages = tempData.staticMessages
    }
}


// MARK: - 角色管理

/// 角色管理扩展
extension PreferencesViewBackend {
    /// 切换到指定索引的角色
    /// - Parameter index: 角色索引
    func switchCharacter(to index: Int) {
        do {
            _ = try controlService.switchCharacter(
                SwitchCharacterRequest(
                    index: index,
                    context: PetControlRequestContext(source: .ui)
                )
            )
        } catch {
            errorAlertMessage = "切换角色失败：\(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    /// 获取当前角色在列表中的索引
    /// - Returns: 当前角色的索引
    func getCurrentCharacterIndex() -> Int {
        return availableCharacters.firstIndex(where: { $0.name == petViewBackend.currentCharacter.name }) ?? 0
    }
}
