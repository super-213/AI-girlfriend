import Foundation
import Combine
import AppKit
import Cocoa

class PetViewBackend: ObservableObject {
    // MARK: - 可绑定的属性
    @Published var currentCharacter: PetCharacter = puppetBear {
        didSet {
            currentGif = currentCharacter.normalGif
        }
    }
    @Published var currentGif: String = puppetBear.normalGif
    @Published var isReacting = false
    @Published var userInput = ""
    @Published var isThinking = false
    @Published var streamedResponse = ""
    
    // MARK: - 资源常量
    private let apiManager = APIManager()
    
    // MARK: - 自动交互定时器
    private var periodicAutoActionTimer: AnyCancellable?
    private let clickAnimationDuration: TimeInterval = 20.0
    
    init() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppDidBecomeActive),
                                               name: NSApplication.didBecomeActiveNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(onAppDidResignActive),
                                               name: NSApplication.didResignActiveNotification,
                                               object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancelAutoActionLoop()
    }
    
    // MARK: - 生命周期
    func onAppear() {
        startAutoActionLoop()
    }
    
    func onDisappear() {
        cancelAutoActionLoop()
        streamedResponse = ""
    }
    
    @objc private func onAppDidBecomeActive() {
        startAutoActionLoop()
    }
    
    @objc private func onAppDidResignActive() {
        // 不取消定时器，保持后台也能持续运行自动互动
    }
    
    // MARK: - 用户交互
    func submitInput() {
        guard !userInput.isEmpty else { return }
        
        // 尝试是否是播放音乐指令
        if userInput.contains("我想听") || userInput.contains("播放") || userInput.contains("来一首") {
            let songName = extractSongName(from: userInput)
            print("🎵 识别到音乐请求：\(songName)")
            playSongInAppleMusic(songName: songName)
            
            // 清空输入并返回，不发送到 AI
            userInput = ""
            return
        }
        
        // 其他指令发送到 AI
        sendRequest(userInput: userInput)
        userInput = ""
    }
    
    func handleTap() {
        guard !isReacting else { return }
        playNextGif()
    }
    
    // MARK: - 切换角色
    func switchToCharacter(_ character: PetCharacter) {
        print("切换角色为：\(character.name)")
        isReacting = false // 停止当前动画反应
        currentCharacter = character
        currentGif = character.normalGif
    }
    
    // MARK: - 播放动画
    private func playNextGif() {
        print("开始播放动画: \(currentCharacter.clickGif)")
        print("当前 isReacting: \(isReacting)")
        
        currentGif = currentCharacter.clickGif
        isReacting = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + clickAnimationDuration) { [weak self] in
            print("动画定时器触发")
            guard let self = self else {
                print("self 已释放")
                return
            }
            self.currentGif = self.currentCharacter.normalGif
            self.isReacting = false
            print("动画已重置，currentGif: \(self.currentGif), isReacting: \(self.isReacting)")
        }
        
        print("设置了 \(clickAnimationDuration) 秒后恢复")
    }
    
    // MARK: - 模型响应
    private func sendRequest(userInput: String) {
        isThinking = true
        streamedResponse = ""
        
        apiManager.sendStreamRequest(userInput: userInput) { newContent in
            DispatchQueue.main.async {
                self.streamedResponse += newContent
            }
        } onComplete: {
            DispatchQueue.main.async {
                self.isThinking = false
            }
        }
    }
    
    // MARK: - 自动定时交互
    private func startAutoActionLoop() {
        scheduleNextAutoAction()
    }
    
    private func scheduleNextAutoAction() {
        let delay = Double.random(in: 270...330)
        print("安排下一次自动互动将在 \(Int(delay)) 秒后执行")
        
        periodicAutoActionTimer = Just(())
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.performAutoAction()
                self?.scheduleNextAutoAction() // 继续下一轮
            }
    }
    
    private func performAutoAction() {
        guard !isReacting else {
            print("当前正在播放动画，跳过自动互动")
            return
        }
        
        print("执行自动互动")
        playNextGif()
        
        let autoMessage = currentCharacter.autoMessages.randomElement() ?? ""
        streamedResponse = autoMessage
    }
    
    private func cancelAutoActionLoop() {
        print("停止自动互动定时器")
        periodicAutoActionTimer?.cancel()
        periodicAutoActionTimer = nil
    }
    // MARK: - 音乐播放控制
    private func extractSongName(from input: String) -> String {
        // 简单去除常见开头关键词
        let keywords = ["我想听", "播放", "来一首", "来点", "帮我放"]
        var result = input
        
        for keyword in keywords {
            if result.contains(keyword) {
                result = result.replacingOccurrences(of: keyword, with: "")
            }
        }

        // 去除“的歌”等尾巴
        result = result.replacingOccurrences(of: "的歌", with: "")
        
        // 去除前后空格
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func playSongInAppleMusic(songName: String) {
        guard let encoded = songName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://music.apple.com/search?term=\(encoded)") else {
            print("无法生成搜索 URL")
            return
        }

        NSWorkspace.shared.open(url)
        sendRequest(userInput: "请以“布偶熊·觅语”的口吻，用80%可爱+20%傲娇的语气回复，说明已经为指挥官打开了 Apple Music 的搜索结果，但因为权限不够无法自动播放，拜托指挥官自己点击第一首播放。语气要甜美俏皮，带一点点撒娇，用颜文字增加表现力，回复结尾加上“布偶熊·觅语随时陪伴指挥官哦～(๑ᴖ◡ᴖ๑)♪”。")
    }
}
