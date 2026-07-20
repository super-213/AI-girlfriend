//
//  PetViewBackend.swift
//  看板娘
//
//  业务服务适配层：业务流程发布 PetStateEvent，视图不再推断状态。
//

import AppKit
import Combine
import Foundation

@MainActor
final class PetViewBackend: ObservableObject {
    @Published var currentCharacter: PetCharacter = puppetBear {
        didSet {
            UserDefaults.standard.set(currentCharacter.id, forKey: "selectedPetCharacterID")
            refreshCurrentAsset()
        }
    }
    @Published private(set) var currentResolvedAsset: PetResolvedAsset?
    @Published private(set) var currentGif: String = puppetBear.normalGif
    @Published var userInput = ""
    @Published var streamedResponse = ""
    @Published var showCommandConfirm = false
    @Published var pendingCommand = ""
    @Published private(set) var isExecutingCommand = false
    @Published private(set) var isRecognizingTrigger = false
    @Published var showOutputBox = false

    let stateCoordinator: PetStateCoordinator

    var isThinking: Bool {
        if isRecognizingTrigger { return true }
        switch stateCoordinator.snapshot.activityState {
        case .thinking, .talking, .automation, .triggered:
            return true
        default:
            return false
        }
    }

    var isBusy: Bool {
        isRecognizingTrigger || isExecutingCommand || stateCoordinator.isBusy
    }

    var isReacting: Bool {
        stateCoordinator.transientEffect == .clicked
    }

    private enum RequestKind {
        case conversation
        case automation
    }

    private let apiManager: APIManager
    private let automationStore: AutomationStore
    private let triggerDispatcher: TriggerDispatcher
    private let assetResolver = PetAssetResolver()
    private var outputBoxHideTimer: AnyCancellable?
    private var periodicAutoActionTimer: AnyCancellable?
    private var memoryCleanupTimer: AnyCancellable?
    private var assetRotationTimer: AnyCancellable?
    private var automationTimer: Timer?
    private var sleepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []

    private var lastUserInput = ""
    private var messageHistory: [[String: String]] = []
    private let maxCommandIterations = 5
    private var commandIterationCount = 0
    private var activeRequestID: UUID?
    private var pendingCommandRunID: UUID?
    private var hasReceivedStreamContent = false

    init(
        apiManager: APIManager = APIManager(),
        automationStore: AutomationStore = .shared,
        triggerDispatcher: TriggerDispatcher = .shared,
        stateCoordinator: PetStateCoordinator? = nil
    ) {
        self.apiManager = apiManager
        self.automationStore = automationStore
        self.triggerDispatcher = triggerDispatcher
        self.stateCoordinator = stateCoordinator ?? PetStateCoordinator()

        currentCharacter = Self.initialCharacter()
        bindState()
        registerNotifications()
        startPeriodicMemoryCleanup()
        observeAutomationChanges()
        scheduleNextAutomationAction()
        startAssetRotation()
        PetControlService.shared.register(petViewBackend: self)
        AppWindowRouter.shared.register(petViewBackend: self)
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
        outputBoxHideTimer?.cancel()
        periodicAutoActionTimer?.cancel()
        memoryCleanupTimer?.cancel()
        assetRotationTimer?.cancel()
        automationTimer?.invalidate()
        sleepTimer?.invalidate()
    }

    func onAppear() {
        startAutoActionLoop()
        scheduleIdleSleepIfNeeded()
    }

    func onDisappear() {
        cancelAutoActionLoop()
    }

    func submitInput() {
        let submittedInput = userInput
        guard !submittedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submitExternalInput(submittedInput)
        userInput = ""
    }

    func submitExternalInput(_ input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        guard !isBusy else {
            streamedResponse = "当前任务还在处理中，请先完成或停止它。"
            revealOutputBox(autoHideAfter: 8)
            return
        }

        noteUserActivity()
        let runID = UUID()
        activeRequestID = runID
        lastUserInput = trimmedInput
        commandIterationCount = 0
        messageHistory = [["role": "system", "content": apiManager.systemPromptContent()]]
        streamedResponse = ""
        revealOutputBox(autoHideAfter: 30)
        isRecognizingTrigger = true

        triggerDispatcher.handleUserInput(
            trimmedInput,
            onExecutionStarted: { [weak self] in
                guard let self, self.activeRequestID == runID else { return }
                self.isRecognizingTrigger = false
                self.stateCoordinator.send(.triggerMatched(runID))
                self.stateCoordinator.send(.triggerStarted(runID))
            },
            completion: { [weak self] result in
                guard let self, self.activeRequestID == runID else { return }
                self.isRecognizingTrigger = false

                switch result {
                case .executed(let message):
                    self.streamedResponse = message
                    self.revealOutputBox(autoHideAfter: 10)
                    if !LocalMP3PlayerService.shared.isPlaying {
                        self.stateCoordinator.send(.triggerCompleted(runID))
                        self.activeRequestID = nil
                    }
                case .failed(let message):
                    self.streamedResponse = "触发器执行失败：\(message)"
                    self.revealOutputBox(autoHideAfter: 15)
                    self.stateCoordinator.send(.triggerFailed(runID, message))
                    self.activeRequestID = nil
                case .noEnabledTriggers, .notMatched:
                    if !self.tryLegacyAppleMusicFallback(trimmedInput, runID: runID) {
                        self.continueChatProcessing(trimmedInput, runID: runID)
                    }
                }
            }
        )
    }

    func submitAutomation(_ automation: AutomationFlow) {
        guard !isBusy else {
            automationStore.markDeferred(automation)
            return
        }

        let runID = UUID()
        activeRequestID = runID
        stateCoordinator.send(.automationStarted(runID))
        streamedResponse = ""
        revealOutputBox(autoHideAfter: 20)

        if let triggerID = automation.triggerId {
            stateCoordinator.send(.triggerStarted(runID))
            let result = triggerDispatcher.runEnabledTrigger(id: triggerID)
            switch result {
            case .executed(let message):
                streamedResponse = message
                revealOutputBox(autoHideAfter: 10)
                if !LocalMP3PlayerService.shared.isPlaying {
                    stateCoordinator.send(.automationCompleted(runID))
                    activeRequestID = nil
                }
            case .failed(let message):
                streamedResponse = "自动化触发器执行失败：\(message)"
                stateCoordinator.send(.automationFailed(runID, message))
                activeRequestID = nil
            case .noEnabledTriggers, .notMatched:
                streamedResponse = "自动化触发器未执行"
                stateCoordinator.send(.automationFailed(runID, "触发器未执行"))
                activeRequestID = nil
            }
        } else {
            let prompt = automation.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                stateCoordinator.send(.automationFailed(runID, "自动化提示词为空"))
                activeRequestID = nil
                return
            }
            lastUserInput = prompt
            commandIterationCount = 0
            messageHistory = [
                ["role": "system", "content": apiManager.systemPromptContent()],
                ["role": "user", "content": prompt]
            ]
            sendRequest(runID: runID, kind: .automation)
        }
    }

    func cancelActiveRequest() {
        guard activeRequestID != nil || isRecognizingTrigger || isExecutingCommand else { return }
        apiManager.cancelStreamRequest()
        activeRequestID = nil
        isRecognizingTrigger = false
        isExecutingCommand = false
        stateCoordinator.send(.resetToIdle)
        streamedResponse = "已停止当前任务。"
        revealOutputBox(autoHideAfter: 6)
    }

    func handleTap() {
        noteUserActivity()
        guard !isReacting, !stateCoordinator.isBusy else { return }
        stateCoordinator.send(.interaction(.clicked, interactionDuration))
    }

    func handleInputFocusChanged(_ focused: Bool) {
        PetWindowController.shared.setInteractionLocked(focused)
        stateCoordinator.send(.listeningChanged(focused))
        if focused { noteUserActivity() }
    }

    func switchToCharacter(_ character: PetCharacter) {
        currentCharacter = character
        stateCoordinator.send(.interaction(.greet, interactionDuration))
    }

    func cycleCharacter() {
        let characters = Self.allPersistedCharacters()
        guard !characters.isEmpty else { return }
        let currentIndex = characters.firstIndex(where: { $0.id == currentCharacter.id }) ?? 0
        switchToCharacter(characters[(currentIndex + 1) % characters.count])
    }

    func confirmAndRunCommand() {
        let command = pendingCommand
        let runID = pendingCommandRunID ?? activeRequestID ?? UUID()
        showCommandConfirm = false
        pendingCommand = ""
        pendingCommandRunID = nil

        guard !command.isEmpty else {
            stateCoordinator.send(.resetToIdle)
            return
        }

        guard CommandExecutionSupport.isCommandSafe(command) else {
            let message = "已阻止危险或交互式命令：\(command)"
            streamedResponse = "[完成] \(message)"
            stateCoordinator.send(.commandFailed(runID, message))
            activeRequestID = nil
            return
        }

        activeRequestID = runID
        isExecutingCommand = true
        streamedResponse = ""
        revealOutputBox(autoHideAfter: 30)
        stateCoordinator.send(.commandStarted(runID))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = CommandExecutionSupport.runShell(command)
            let trimmedOutput = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                guard let self, self.activeRequestID == runID else { return }
                self.isExecutingCommand = false
                self.commandIterationCount += 1

                guard self.commandIterationCount <= self.maxCommandIterations else {
                    let message = "命令执行次数过多，已停止自动执行"
                    self.streamedResponse = "[完成] \(message)"
                    self.stateCoordinator.send(.commandFailed(runID, message))
                    self.activeRequestID = nil
                    return
                }

                let resultText = """
                执行完毕
                命令: \(command)
                退出码: \(result.0)
                输出:
                \(trimmedOutput.isEmpty ? "(无输出)" : trimmedOutput)
                """
                self.messageHistory.append(["role": "user", "content": resultText])
                self.sendRequest(runID: runID, kind: .conversation)
            }
        }
    }

    func cancelPendingCommand() {
        showCommandConfirm = false
        pendingCommand = ""
        pendingCommandRunID = nil
        activeRequestID = nil
        streamedResponse = "[完成] 已取消执行命令"
        revealOutputBox(autoHideAfter: 8)
        stateCoordinator.send(.resetToIdle)
    }

    func revealOutputBox(autoHideAfter duration: TimeInterval = 15) {
        outputBoxHideTimer?.cancel()
        showOutputBox = true
        outputBoxHideTimer = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.dismissOutputBox() }
    }

    func dismissOutputBox() {
        outputBoxHideTimer?.cancel()
        outputBoxHideTimer = nil
        showOutputBox = false
    }

    private func continueChatProcessing(_ input: String, runID: UUID) {
        messageHistory.append(["role": "user", "content": input])
        sendRequest(runID: runID, kind: .conversation)
    }

    private func sendRequest(runID: UUID, kind: RequestKind) {
        activeRequestID = runID
        hasReceivedStreamContent = false
        streamedResponse = ""
        revealOutputBox(autoHideAfter: 30)

        if kind == .conversation {
            stateCoordinator.send(.conversationStarted(runID))
        }

        apiManager.sendStreamRequest(
            messages: messageHistory,
            onReceive: { [weak self] chunk in
                guard let self, self.activeRequestID == runID, !chunk.isEmpty else { return }
                if !self.hasReceivedStreamContent {
                    self.hasReceivedStreamContent = true
                    switch kind {
                    case .conversation: self.stateCoordinator.send(.conversationStreamStarted(runID))
                    case .automation: self.stateCoordinator.send(.automationStreamStarted(runID))
                    }
                }
                self.streamedResponse += chunk
                if self.streamedResponse.count > 5_000 {
                    self.streamedResponse = String(self.streamedResponse.suffix(5_000))
                }
            },
            onComplete: { [weak self] in
                guard let self, self.activeRequestID == runID else { return }
                let outcome = self.handleAssistantReply(runID: runID)
                switch outcome {
                case .command, .needsInput:
                    break
                case .normal:
                    switch kind {
                    case .conversation: self.stateCoordinator.send(.conversationCompleted(runID))
                    case .automation: self.stateCoordinator.send(.automationCompleted(runID))
                    }
                    self.revealOutputBox(autoHideAfter: self.configuredBubbleDuration)
                    self.activeRequestID = nil
                }
            },
            onError: { [weak self] error in
                guard let self, self.activeRequestID == runID else { return }
                let message = error.localizedDescription
                self.streamedResponse = "请求失败：\(message)"
                self.revealOutputBox(autoHideAfter: 15)
                switch kind {
                case .conversation: self.stateCoordinator.send(.conversationFailed(runID, message))
                case .automation: self.stateCoordinator.send(.automationFailed(runID, message))
                }
                self.activeRequestID = nil
            }
        )
    }

    private enum AssistantOutcome { case normal, command, needsInput }

    private func handleAssistantReply(runID: UUID) -> AssistantOutcome {
        let reply = streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else {
            streamedResponse = "模型没有返回内容，需要你补充说明或重试。"
            stateCoordinator.send(.conversationNeedsInput(runID))
            return .needsInput
        }
        messageHistory.append(["role": "assistant", "content": reply])

        if reply.localizedCaseInsensitiveContains("[需要输入]") {
            stateCoordinator.send(.conversationNeedsInput(runID))
            return .needsInput
        }
        if CommandExecutionSupport.isCompletionReply(reply) || isExecutingCommand {
            return .normal
        }
        guard let command = CommandExecutionSupport.extractCommand(from: streamedResponse) else {
            return .normal
        }

        let normalized = CommandExecutionSupport.normalizeCommand(command, basedOn: lastUserInput)
        pendingCommand = normalized
        pendingCommandRunID = runID
        if normalized != command, let range = streamedResponse.range(of: command) {
            streamedResponse.replaceSubrange(range, with: normalized)
        }
        if !CommandExecutionSupport.hasCommandTag(in: streamedResponse) {
            streamedResponse += "\n[命令] \(normalized)"
        }
        showCommandConfirm = true
        stateCoordinator.send(.commandConfirmationRequested(runID))
        return .command
    }

    private func tryLegacyAppleMusicFallback(_ input: String, runID: UUID) -> Bool {
        guard input.contains("我想听") || input.contains("播放") || input.contains("来一首") else {
            return false
        }
        stateCoordinator.send(.audioStarted(runID))
        streamedResponse = MusicPlayerService.playSong(named: MusicPlayerService.extractSongName(from: input))
        revealOutputBox(autoHideAfter: 10)
        stateCoordinator.send(.audioCompleted(runID))
        activeRequestID = nil
        return true
    }

    private func bindState() {
        stateCoordinator.$snapshot
            .combineLatest(stateCoordinator.$transientEffect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshCurrentAsset()
                self?.scheduleIdleSleepIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func refreshCurrentAsset() {
        currentResolvedAsset = assetResolver.resolve(
            character: currentCharacter,
            state: stateCoordinator.snapshot.renderedState,
            transientEffect: stateCoordinator.transientEffect
        )
        currentGif = currentResolvedAsset?.asset.location ?? ""
    }

    private func startAssetRotation() {
        assetRotationTimer = Timer.publish(every: PetAssetResolver.rotationInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshCurrentAsset() }
    }

    private func noteUserActivity() {
        sleepTimer?.invalidate()
        if stateCoordinator.snapshot.activityState == .sleeping {
            stateCoordinator.send(.resetToIdle)
        }
        scheduleIdleSleepIfNeeded()
    }

    private func scheduleIdleSleepIfNeeded() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard stateCoordinator.snapshot.activityState == .idle else { return }
        let defaults = UserDefaults.standard
        let minutes = defaults.object(forKey: "petSleepMinutes") == nil ? 6 : defaults.double(forKey: "petSleepMinutes")
        guard minutes > 0 else { return }
        let timer = Timer(timeInterval: minutes * 60, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stateCoordinator.send(.idleTimeoutReached) }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
    }

    private func startAutoActionLoop() {
        guard periodicAutoActionTimer == nil else { return }
        scheduleNextAutoAction()
    }

    private func scheduleNextAutoAction() {
        let delay = Double.random(in: 270...330)
        periodicAutoActionTimer = Just(())
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.periodicAutoActionTimer = nil
                self?.performAutoAction()
                self?.scheduleNextAutoAction()
            }
    }

    private func performAutoAction() {
        let state = stateCoordinator.snapshot.activityState
        guard state == .idle || state == .sleeping else { return }
        stateCoordinator.send(.resetToIdle)
        stateCoordinator.send(.interaction(.greet, interactionDuration))
        if let data = UserDefaults.standard.data(forKey: "staticMessages"),
           let messages = try? JSONDecoder().decode([String].self, from: data),
           !messages.isEmpty {
            streamedResponse = messages.randomElement() ?? ""
        } else {
            streamedResponse = currentCharacter.autoMessages.randomElement() ?? ""
        }
        revealOutputBox(autoHideAfter: 10)
    }

    private func cancelAutoActionLoop() {
        periodicAutoActionTimer?.cancel()
        periodicAutoActionTimer = nil
    }

    private func observeAutomationChanges() {
        automationStore.$automations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleNextAutomationAction() }
            .store(in: &cancellables)
    }

    private func scheduleNextAutomationAction() {
        automationTimer?.invalidate()
        automationTimer = nil
        guard let nextDate = automationStore.nextEnabledAutomationDate() else { return }
        let interval = max(nextDate.timeIntervalSinceNow, 1)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runDueAutomationIfPossible()
                self?.scheduleNextAutomationAction()
            }
        }
        timer.tolerance = min(max(interval * 0.1, 1), 60)
        RunLoop.main.add(timer, forMode: .common)
        automationTimer = timer
    }

    private func runDueAutomationIfPossible() {
        guard let automation = automationStore.dueAutomations().sorted(by: {
            ($0.nextRunAt ?? .distantFuture) < ($1.nextRunAt ?? .distantFuture)
        }).first else { return }
        guard !isBusy else {
            automationStore.markDeferred(automation)
            return
        }
        automationStore.markCompleted(automation)
        submitAutomation(automation)
    }

    private func startPeriodicMemoryCleanup() {
        memoryCleanupTimer = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { _ in MemoryOptimizer.shared.periodicCleanup() }
    }

    private var configuredBubbleDuration: TimeInterval {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "bubbleAutoHideDuration") == nil
            ? 15
            : max(defaults.double(forKey: "bubbleAutoHideDuration"), 5)
    }

    private var interactionDuration: TimeInterval? {
        guard let asset = currentCharacter.interactionAssets.first else { return nil }
        if let preferredDuration = asset.preferredDuration { return preferredDuration }
        guard asset.type == .gif, !asset.loop else { return nil }
        return max(GIFDurationCalculator.getDuration(for: asset.location) * 0.9, 0.5)
    }

    private func registerNotifications() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.startAutoActionLoop() }
        })
        notificationObservers.append(center.addObserver(forName: .petAudioDidStart, object: nil, queue: .main) { [weak self] notification in
            guard let runID = notification.object as? UUID else { return }
            Task { @MainActor in
                self?.stateCoordinator.send(.audioStarted(runID))
            }
        })
        notificationObservers.append(center.addObserver(forName: .petAudioDidFinish, object: nil, queue: .main) { [weak self] notification in
            guard let runID = notification.object as? UUID else { return }
            Task { @MainActor in
                self?.stateCoordinator.send(.audioCompleted(runID))
                self?.activeRequestID = nil
            }
        })
        notificationObservers.append(center.addObserver(forName: Notification.Name("SettingsChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleIdleSleepIfNeeded() }
        })
    }

    private static func initialCharacter() -> PetCharacter {
        let characters = allPersistedCharacters()
        let selectedID = UserDefaults.standard.string(forKey: "selectedPetCharacterID")
        return characters.first(where: { $0.id == selectedID }) ?? characters.first ?? puppetBear
    }

    private static func allPersistedCharacters() -> [PetCharacter] {
        var characters = availableCharacters
        if let data = UserDefaults.standard.data(forKey: "customCharacters"),
           let custom = try? JSONDecoder().decode([PetCharacter].self, from: data) {
            characters.append(contentsOf: custom)
        }
        return characters
    }
}
