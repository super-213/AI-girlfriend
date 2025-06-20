import Foundation
import Combine
import AppKit

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
        streamedResponse += (streamedResponse.isEmpty ? "" : "\n") + autoMessage
    }

    private func cancelAutoActionLoop() {
        print("停止自动互动定时器")
        periodicAutoActionTimer?.cancel()
        periodicAutoActionTimer = nil
    }
}
