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
    
    // MARK: - 资源常量
    
    /// API管理器实例
    private let apiManager = APIManager()
    
    // MARK: - 自动交互定时器
    
    /// 定期自动行为的定时器
    private var periodicAutoActionTimer: AnyCancellable?
    
    /// 定期内存清理定时器
    private var memoryCleanupTimer: AnyCancellable?
    
    // MARK: - 初始化
    
    /// 初始化后端并注册通知观察者
    init() {
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
    }
    
    /// 清理资源和观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancelAutoActionLoop()
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
        guard !userInput.isEmpty else { return }
        
        if userInput.contains("我想听") || userInput.contains("播放") || userInput.contains("来一首") {
            let songName = MusicPlayerService.extractSongName(from: userInput)
            streamedResponse = MusicPlayerService.playSong(named: songName)
            userInput = ""
            return
        }
        
        sendRequest(userInput: userInput)
        userInput = ""
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
    private func sendRequest(userInput: String) {
        isThinking = true
        streamedResponse = ""
        
        apiManager.sendStreamRequest(userInput: userInput) { newContent in
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
            }
        }
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
    
    // MARK: - 内存管理
    
    /// 启动定期内存清理（每5分钟）
    private func startPeriodicMemoryCleanup() {
        memoryCleanupTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MemoryOptimizer.shared.periodicCleanup()
                #if DEBUG
                print("执行定期内存清理")
                #endif
            }
    }
}
