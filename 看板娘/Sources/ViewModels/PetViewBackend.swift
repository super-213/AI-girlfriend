//
//  PetViewBackend.swift
//  桌面宠物应用
//
//  宠物视图的业务逻辑和状态管理
//

import Foundation
import Combine
import AppKit
import Cocoa
import ImageIO

// MARK: - 宠物视图后端

/// 宠物视图的后端逻辑控制器
/// 负责管理角色状态、用户交互、API通信和自动行为
class PetViewBackend: ObservableObject {
    // MARK: - 可绑定属性
    
    /// 当前选中的角色
    @Published var currentCharacter: PetCharacter = puppetBear {
        didSet {
            currentGif = currentCharacter.normalGif
        }
    }
    
    /// 当前显示的GIF文件名
    @Published var currentGif: String = puppetBear.normalGif
    
    /// 是否正在播放反应动画
    @Published var isReacting = false
    
    /// 用户输入的文本
    @Published var userInput = ""
    
    /// 是否正在等待AI响应
    @Published var isThinking = false
    
    /// AI流式响应的累积文本
    @Published var streamedResponse = ""
    
    /// 是否显示命令确认弹窗
    @Published var showCommandConfirm = false
    
    /// 待执行的命令
    @Published var pendingCommand: String = ""
    
    /// 是否正在执行命令
    @Published var isExecutingCommand = false
    
    /// 最近一次用户输入
    private var lastUserInput: String = ""
    
    /// 会话消息历史
    private var messageHistory: [[String: String]] = []
    
    /// 连续命令执行上限
    private let maxCommandIterations = 5
    
    /// 当前命令循环次数
    private var commandIterationCount = 0
    
    // MARK: - 资源常量
    
    /// API管理器实例
    private let apiManager = APIManager()

    /// 自动化流程存储
    private let automationStore = AutomationStore.shared
    
    // MARK: - 自动交互定时器
    
    /// 定期自动行为的定时器
    private var periodicAutoActionTimer: AnyCancellable?
    
    /// 定期内存清理定时器
    private var memoryCleanupTimer: AnyCancellable?

    /// 自动化流程调度定时器
    private var automationTimer: Timer?

    /// 自动化数据变更监听
    private var automationStoreCancellable: AnyCancellable?
    
    // MARK: - 初始化
    
    /// 初始化后端并注册通知观察者
    init() {
        PetControlService.shared.register(petViewBackend: self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppDidBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppDidResignActive),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
        
        // 启动定期内存清理（每5分钟）
        startPeriodicMemoryCleanup()
        observeAutomationChanges()
        scheduleNextAutomationAction()
    }
    
    /// 清理资源和观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancelAutoActionLoop()
        automationTimer?.invalidate()
        automationTimer = nil
        automationStoreCancellable?.cancel()
        memoryCleanupTimer?.cancel()
    }
    
    // MARK: - 生命周期
    
    /// 视图出现时调用
    func onAppear() {
        startAutoActionLoop()
    }
    
    /// 视图消失时调用
    func onDisappear() {
        cancelAutoActionLoop()
        streamedResponse = ""
    }
    
    /// 应用激活时调用
    @objc private func onAppDidBecomeActive() {
        startAutoActionLoop()
    }
    
    /// 应用失去焦点时调用
    @objc private func onAppDidResignActive() {
        // 不取消定时器，保持后台也能持续运行自动互动
    }
    
    // MARK: - 用户交互
    
    /// 提交用户输入
    /// 处理音乐播放请求或发送到AI模型
    func submitInput() {
        let submittedInput = userInput
        guard !submittedInput.isEmpty else { return }
        submitExternalInput(submittedInput)
        userInput = ""
    }

    /// 供控制服务和机器入口调用的结构化消息提交入口
    func submitExternalInput(_ input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        lastUserInput = trimmedInput
        commandIterationCount = 0
        messageHistory = [["role": "system", "content": apiManager.systemPromptContent()]]
        
        if trimmedInput.contains("我想听") || trimmedInput.contains("播放") || trimmedInput.contains("来一首") {
            let songName = MusicPlayerService.extractSongName(from: trimmedInput)
            streamedResponse = MusicPlayerService.playSong(named: songName)
            return
        }

        messageHistory.append(["role": "user", "content": trimmedInput])
        sendRequest()
    }

    /// 提交自动化提示词，输出沿用主宠物对话输出框
    private func submitAutomationPrompt(_ prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        submitExternalInput(trimmedPrompt)
    }
    
    /// 处理宠物点击事件
    func handleTap() {
        guard !isReacting else { return }
        playNextGif()
    }
    
    /// 切换到指定角色
    /// - Parameter character: 要切换到的角色
    func switchToCharacter(_ character: PetCharacter) {
        isReacting = false
        currentCharacter = character
        currentGif = character.normalGif
    }
    
    /// 播放角色的点击动画
    private func playNextGif() {
        currentGif = currentCharacter.clickGif
        isReacting = true
        
        // 使用GIF时长计算服务
        let calculatedDuration = GIFDurationCalculator.getDuration(for: currentCharacter.clickGif)
        
        // 减少10%的时长，让切换更及时（避免GIF已播完但还在等待的情况）
        let duration = calculatedDuration * 0.9
        
        #if DEBUG
        print("GIF: \(currentCharacter.clickGif), 计算时长: \(calculatedDuration)秒, 实际使用: \(duration)秒")
        #endif
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self else { return }
            self.currentGif = self.currentCharacter.normalGif
            self.isReacting = false
            #if DEBUG
            print("切换回静止状态")
            #endif
        }
    }
    
    // MARK: - 模型响应
    
    /// 发送用户输入到AI模型
    /// - Parameter userInput: 用户输入的文本
    private func sendRequest() {
        isThinking = true
        streamedResponse = ""
        
        apiManager.sendStreamRequest(messages: messageHistory) { newContent in
            DispatchQueue.main.async {
                self.streamedResponse += newContent
                
                // 限制响应文本长度，避免内存无限增长
                if self.streamedResponse.count > 5000 {
                    self.streamedResponse = String(self.streamedResponse.suffix(5000))
                }
            }
        } onComplete: {
            DispatchQueue.main.async {
                self.isThinking = false
                self.handleAssistantReply()
            }
        }
    }
    
    // MARK: - 命令执行管道
    
    private func handleAssistantReply() {
        let assistantReply = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assistantReply.isEmpty {
            messageHistory.append(["role": "assistant", "content": assistantReply])
        }
        
        if isCompletionReply(assistantReply) {
            return
        }
        
        guard !isExecutingCommand else { return }
        guard let command = extractCommand(from: streamedResponse) else { return }
        let normalized = normalizeCommand(command, basedOn: lastUserInput)
        pendingCommand = normalized
        
        if normalized != command {
            if let range = streamedResponse.range(of: command) {
                streamedResponse.replaceSubrange(range, with: normalized)
            }
        }
        
        if !hasCommandTag(in: streamedResponse) {
            streamedResponse += "\n[命令] \(normalized)"
        }
        
        showCommandConfirm = true
    }
    
    private func extractCommand(from text: String) -> String? {
        if let command = extractCommandByToken(text, token: "命令:") {
            return command
        }
        
        let tags = ["[命令]", "[系统指令]", "[系统命令]", "[command]"]
        
        for tag in tags {
            if let range = text.range(of: tag) {
                let tail = text[range.upperBound...]
                let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
                let command = line.map(String.init) ?? String(tail)
                let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        
        let lines = text.split(separator: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for tag in tags {
                if trimmed.hasPrefix(tag) {
                    let cleaned = trimmed.replacingOccurrences(of: tag, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty {
                        return cleaned
                    }
                }
            }
        }

        if let fallback = extractCommandWithoutTag(from: text) {
            return fallback
        }

        return nil
    }

    private func extractCommandByToken(_ text: String, token: String) -> String? {
        guard let range = text.range(of: token) else { return nil }
        let tail = text[range.upperBound...]
        let line = tail.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        let command = line.map(String.init) ?? String(tail)
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func extractCommandWithoutTag(from text: String) -> String? {
        let candidates = ["ls", "zip", "tar", "cp", "mv", "cat", "pwd", "mkdir", "rmdir"]
        let lines = text.split(separator: "\n")
        for line in lines {
            let raw = String(line)
            for cmd in candidates {
                if let range = raw.range(of: "\(cmd) ") ?? (raw.hasPrefix("\(cmd)\t") ? raw.range(of: cmd) : nil) {
                    let tail = raw[range.lowerBound...]
                    let cleaned = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.count > 1 {
                        return cleaned
                    }
                }
            }
        }
        return nil
    }
    
    private func hasCommandTag(in text: String) -> Bool {
        let tags = ["[命令]", "[系统指令]", "[系统命令]", "[command]"]
        return tags.contains { text.contains($0) }
    }
    
    private func isCompletionReply(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("完成:") || trimmed.hasPrefix("[完成]")
    }
    
    private func normalizeCommand(_ command: String, basedOn input: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let inputLower = input.lowercased()
        let listingIntent = input.contains("目录") || input.contains("文件") || input.contains("列表")
            || inputLower.contains("list")
        
        if listingIntent, lower.hasPrefix("ls -l"), !lower.contains(" -a") {
            if lower.hasPrefix("ls -lh") {
                return trimmed.replacingOccurrences(of: "ls -lh", with: "ls -lha")
            }
            return trimmed.replacingOccurrences(of: "ls -l", with: "ls -la")
        }
        
        return trimmed
    }
    
    func confirmAndRunCommand() {
        let command = pendingCommand
        showCommandConfirm = false
        pendingCommand = ""
        
        guard !command.isEmpty else { return }
        
        guard isCommandSafe(command) else {
            streamedResponse = "[完成] 已阻止危险或交互式命令: \(command)"
            return
        }
        
        isExecutingCommand = true
        isThinking = true
        streamedResponse = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            let (exitCode, output) = self.runShell(command)
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            DispatchQueue.main.async {
                self.isExecutingCommand = false
                self.commandIterationCount += 1
                if self.commandIterationCount > self.maxCommandIterations {
                    self.streamedResponse = "[完成] 命令执行次数过多，已停止自动执行"
                    return
                }
                let resultText = """
                执行完毕
                命令: \(command)
                退出码: \(exitCode)
                输出:
                \(trimmedOutput.isEmpty ? "(无输出)" : trimmedOutput)
                """
                self.messageHistory.append(["role": "user", "content": resultText])
                self.sendRequest()
            }
        }
    }
    
    func cancelPendingCommand() {
        showCommandConfirm = false
        pendingCommand = ""
        streamedResponse = "[完成] 已取消执行命令"
    }
    
    private func isCommandSafe(_ command: String) -> Bool {
        let lower = command.lowercased()
        let allowPrefixes = [
            "ls", "pwd", "cat", "zip", "tar", "cp", "mv", "mkdir", "rmdir"
        ]
        if allowPrefixes.contains(where: { lower.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix($0 + " ") || lower == $0 }) {
            if lower.contains("rm -rf") || lower.contains("sudo") {
                return false
            }
            return true
        }
        let blockedTokens = [
            "rm -rf", "sudo", "shutdown", "reboot", "mkfs", "dd ", ">:",
            "vi ", "nano", "top", "htop", "less", "more", "ssh "
        ]
        if blockedTokens.contains(where: { lower.contains($0) }) {
            return false
        }
        return true
    }
    
    private func runShell(_ command: String) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
        } catch {
            return (1, "无法启动命令: \(error.localizedDescription)")
        }
        
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    
    // MARK: - 自动定时交互
    
    /// 启动自动行为循环
    private func startAutoActionLoop() {
        scheduleNextAutoAction()
    }
    
    /// 调度下一次自动行为
    private func scheduleNextAutoAction() {
        let delay = Double.random(in: 270...330)
        periodicAutoActionTimer = Just(())
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performAutoAction()
                self?.scheduleNextAutoAction()
            }
    }
    
    /// 执行自动行为（播放动画和显示消息）
    private func performAutoAction() {
        guard !isReacting else { return }
        playNextGif()
        
        // 清理旧的响应文本，避免内存累积
        streamedResponse = ""
        
        // 优先使用静态提示词，如果没有则使用角色的 autoMessages
        if let data = UserDefaults.standard.data(forKey: "staticMessages"),
           let staticMessages = try? JSONDecoder().decode([String].self, from: data),
           !staticMessages.isEmpty {
            streamedResponse = staticMessages.randomElement() ?? ""
        } else {
            streamedResponse = currentCharacter.autoMessages.randomElement() ?? ""
        }
    }
    
    /// 取消自动行为循环
    private func cancelAutoActionLoop() {
        periodicAutoActionTimer?.cancel()
        periodicAutoActionTimer = nil
    }

    // MARK: - 自动化流程调度

    private func observeAutomationChanges() {
        automationStoreCancellable = automationStore.$automations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleNextAutomationAction()
            }
    }

    private func scheduleNextAutomationAction() {
        automationTimer?.invalidate()
        automationTimer = nil

        guard let nextDate = automationStore.nextEnabledAutomationDate() else { return }

        let interval = max(nextDate.timeIntervalSinceNow, 1)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.handleAutomationTimer()
        }
        timer.tolerance = min(max(interval * 0.1, 1), 60)
        RunLoop.main.add(timer, forMode: .common)
        automationTimer = timer
    }

    private func handleAutomationTimer() {
        automationTimer?.invalidate()
        automationTimer = nil
        runDueAutomationIfPossible()
        scheduleNextAutomationAction()
    }

    private func runDueAutomationIfPossible() {
        guard let automation = automationStore.dueAutomations().sorted(by: {
            ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture)
        }).first else {
            return
        }

        guard !isThinking, !isExecutingCommand else {
            automationStore.markDeferred(automation)
            return
        }

        automationStore.markCompleted(automation)
        submitAutomationPrompt(automation.prompt)
    }
    
    // MARK: - 内存管理
    
    /// 启动定期内存清理（每5分钟）
    private func startPeriodicMemoryCleanup() {
        memoryCleanupTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                _ = self // 知道 self 被捕获了
                MemoryOptimizer.shared.periodicCleanup()
                #if DEBUG
                print("执行定期内存清理")
                #endif
            }
    }
}
