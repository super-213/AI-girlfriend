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
final class PetStreamedResponseStore: ObservableObject {
    @Published fileprivate(set) var text = ""

    fileprivate func replace(with text: String) {
        self.text = text
    }

    fileprivate func append(_ text: String, limit: Int) {
        self.text += text
        if self.text.count > limit {
            self.text = String(self.text.suffix(limit))
        }
    }
}

@MainActor
final class PetViewBackend: ObservableObject {
    @Published var currentCharacter: PetCharacter = puppetBear {
        didSet {
            UserDefaults.standard.set(currentCharacter.id, forKey: "selectedPetCharacterID")
            refreshConversationStyle()
            refreshCurrentAsset()
        }
    }
    @Published private(set) var conversationStyle: PetConversationStyle = .default
    @Published private(set) var currentResolvedAsset: PetResolvedAsset?
    @Published private(set) var currentGif: String = puppetBear.normalGif
    @Published var showCommandConfirm = false
    @Published var pendingCommand = ""
    @Published private(set) var isExecutingCommand = false
    @Published private(set) var isRecognizingTrigger = false
    @Published private(set) var isCompactingContext = false
    @Published var showOutputBox = false
    @Published private(set) var pendingAttachments: [LocalFileAttachment] = []
    @Published private(set) var invocationOptions: [AgentInvocationOption] = []

    let stateCoordinator: PetStateCoordinator
    let streamedResponseStore = PetStreamedResponseStore()

    var streamedResponse: String {
        get { streamedResponseStore.text }
        set { streamedResponseStore.replace(with: newValue) }
    }

    var isThinking: Bool {
        if isRecognizingTrigger || isCompactingContext { return true }
        switch stateCoordinator.snapshot.activityState {
        case .thinking, .talking, .automation, .triggered:
            return true
        default:
            return false
        }
    }

    var isBusy: Bool {
        isRecognizingTrigger || isExecutingCommand || isCompactingContext || stateCoordinator.isBusy
    }

    var isReacting: Bool {
        stateCoordinator.transientEffect == .clicked
    }

    private enum AgentRequestKind {
        case conversation
        case automation
    }

    private let apiManager: APIManager
    private lazy var agentRuntime = AgentRuntime(apiManager: apiManager) { [weak self, apiManager] in
        apiManager.systemPromptContent(basePrompt: self?.conversationStyle.systemPrompt)
    }
    private let automationStore: AutomationStore
    private let triggerDispatcher: TriggerDispatcher
    private let codexTaskMonitor: CodexTaskMonitor
    private let conversationStore: DialogConversationStore
    private let conversationStoreSourceID = UUID()
    private let assetResolver = PetAssetResolver()
    private var outputBoxHideTimer: AnyCancellable?
    private var periodicAutoActionTimer: AnyCancellable?
    private var assetRotationTimer: AnyCancellable?
    private var automationTimer: Timer?
    private var sleepTimer: Timer?
    private var conversationExpirationTimer: Timer?
    private var petConversationSession = PetConversationSession()
    private var petConversationID: UUID?
    private var petDialogMessages: [DialogMessage] = []
    private var activePetAssistantMessageID: UUID?
    private var cancellables = Set<AnyCancellable>()
    private var notificationObservers: [NSObjectProtocol] = []

    private var activeRequestID: UUID? {
        didSet {
            guard oldValue != nil, activeRequestID == nil else { return }
            Task { @MainActor [weak self] in
                self?.showPendingCodexAnnouncementIfPossible()
            }
        }
    }
    private var activeRequestKind: AgentRequestKind?
    private var pendingCodexAnnouncements: [String] = []
    private var hasReceivedStreamContent = false
    private lazy var streamTextCoalescer = StreamingTextCoalescer { [weak self] text in
        self?.appendStreamedResponse(text)
    }

    init(
        apiManager: APIManager = APIManager(),
        automationStore: AutomationStore = .shared,
        triggerDispatcher: TriggerDispatcher = .shared,
        codexTaskMonitor: CodexTaskMonitor = .shared,
        conversationStore: DialogConversationStore = .shared,
        stateCoordinator: PetStateCoordinator? = nil
    ) {
        self.apiManager = apiManager
        self.automationStore = automationStore
        self.triggerDispatcher = triggerDispatcher
        self.codexTaskMonitor = codexTaskMonitor
        self.conversationStore = conversationStore
        self.stateCoordinator = stateCoordinator ?? PetStateCoordinator()

        currentCharacter = Self.initialCharacter()
        invocationOptions = AgentInvocationCatalog.options()
        prefetchInteractionDurations()
        refreshConversationStyle()
        configureAgentRuntime()
        bindConversationStore()
        restorePersistedPetConversation()
        bindState()
        bindCodexMonitor()
        codexTaskMonitor.start()
        registerNotifications()
        observeAutomationChanges()
        scheduleNextAutomationAction()
        startAssetRotation()
        PetControlService.shared.register(petViewBackend: self)
        AppWindowRouter.shared.register(petViewBackend: self)
    }

    deinit {
        MainActor.assumeIsolated {
            notificationObservers.forEach(NotificationCenter.default.removeObserver)
            outputBoxHideTimer?.cancel()
            periodicAutoActionTimer?.cancel()
            assetRotationTimer?.cancel()
            automationTimer?.invalidate()
            sleepTimer?.invalidate()
            conversationExpirationTimer?.invalidate()
        }
    }

    func onAppear() {
        startAutoActionLoop()
        scheduleIdleSleepIfNeeded()
    }

    func onDisappear() {
        cancelAutoActionLoop()
    }

    func submitExternalInput(_ input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        guard !isBusy else {
            streamedResponse = "当前任务还在处理中，请先完成或停止它。"
            revealOutputBox(autoHideAfter: 8)
            return
        }

        refreshInvocationOptions()
        let submission = AgentInvocationParser.submission(
            from: trimmedInput,
            options: invocationOptions
        )

        noteUserActivity()
        let runID = UUID()
        activeRequestID = runID
        streamedResponse = ""
        revealOutputBox(autoHideAfter: 30)

        let attachments = pendingAttachments
        if !attachments.isEmpty {
            pendingAttachments.removeAll()
            let prompt = FileAttachmentPromptBuilder.prompt(
                userInstruction: submission.instruction,
                attachments: attachments
            )
            continueChatProcessing(
                prompt,
                runID: runID,
                imagePaths: attachments.filter(\.isImage).map(\.path),
                explicitInvocation: submission.invocation,
                visibleText: submission.visibleText.isEmpty ? "请分析这些附件" : submission.visibleText,
                attachments: attachments
            )
            return
        }

        if let invocation = submission.invocation {
            continueChatProcessing(
                submission.instruction,
                runID: runID,
                explicitInvocation: invocation,
                visibleText: submission.visibleText
            )
            return
        }

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
                        self.activeRequestKind = nil
                    }
                case .failed(let message):
                    self.streamedResponse = "触发器执行失败：\(message)"
                    self.revealOutputBox(autoHideAfter: 15)
                    self.stateCoordinator.send(.triggerFailed(runID, message))
                    self.activeRequestID = nil
                    self.activeRequestKind = nil
                case .noEnabledTriggers, .notMatched:
                    if !self.tryLegacyAppleMusicFallback(trimmedInput, runID: runID) {
                        self.continueChatProcessing(trimmedInput, runID: runID)
                    }
                }
            }
        )
    }

    @discardableResult
    func attachFiles(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls {
            guard url.isFileURL else { continue }
            let attachment = LocalFileAttachment(url: url)
            guard FileManager.default.fileExists(atPath: attachment.path),
                  !pendingAttachments.contains(where: { $0.path == attachment.path }),
                  pendingAttachments.count < 8 else { continue }
            pendingAttachments.append(attachment)
            added += 1
        }
        if added > 0 {
            AgentFileAccessStore.shared.grantSessionAccess(to: urls)
            noteUserActivity()
            stateCoordinator.send(.interaction(.attention, 1.2))
        }
        return added
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func clearAttachments() {
        pendingAttachments.removeAll()
    }

    func refreshInvocationOptions() {
        invocationOptions = AgentInvocationCatalog.options()
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
            agentRuntime.startNewConversation()
            activeRequestKind = .automation
            agentRuntime.send(prompt)
        }
    }

    func cancelActiveRequest() {
        guard activeRequestID != nil || isRecognizingTrigger || isExecutingCommand || isCompactingContext else { return }
        let cancelledKind = activeRequestKind
        streamTextCoalescer.reset()
        agentRuntime.cancel()
        apiManager.cancelStreamRequest()
        activeRequestID = nil
        activeRequestKind = nil
        isRecognizingTrigger = false
        isCompactingContext = false
        isExecutingCommand = false
        showCommandConfirm = false
        pendingCommand = ""
        stateCoordinator.send(.resetToIdle)
        streamedResponse = "已停止当前任务。"
        revealOutputBox(autoHideAfter: 6)
        if cancelledKind == .conversation {
            recordPetConversationAndScheduleExpiration()
        }
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
        prefetchInteractionDurations()
        stateCoordinator.send(.interaction(.greet, interactionDuration))
    }

    func cycleCharacter() {
        let characters = Self.allPersistedCharacters()
        guard !characters.isEmpty else { return }
        let currentIndex = characters.firstIndex(where: { $0.id == currentCharacter.id }) ?? 0
        switchToCharacter(characters[(currentIndex + 1) % characters.count])
    }

    func confirmAndRunCommand() {
        showCommandConfirm = false
        pendingCommand = ""
        agentRuntime.approvePendingTool()
    }

    func cancelPendingCommand() {
        showCommandConfirm = false
        pendingCommand = ""
        agentRuntime.declinePendingTool()
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

    private func continueChatProcessing(
        _ input: String,
        runID: UUID,
        imagePaths: [String] = [],
        explicitInvocation: AgentInvocation? = nil,
        visibleText: String? = nil,
        attachments: [LocalFileAttachment] = []
    ) {
        restorePetConversationForNextInput()
        if petConversationID == nil {
            petConversationID = UUID()
            petDialogMessages = []
        }
        petDialogMessages.append(DialogMessage(
            role: .user,
            content: visibleText ?? input,
            attachments: attachments
        ))
        activeRequestID = runID
        activeRequestKind = .conversation
        streamTextCoalescer.reset()
        streamedResponse = ""
        hasReceivedStreamContent = false
        revealOutputBox(autoHideAfter: 30)
        agentRuntime.send(
            input,
            imagePaths: imagePaths,
            explicitInvocation: explicitInvocation
        )
        persistPetConversation(at: .now)
    }

    private func configureAgentRuntime() {
        agentRuntime.onContextCompactionStarted = { [weak self] in
            guard let self else { return }
            self.isCompactingContext = true
            self.streamedResponse = "正在压缩较早的会话上下文…"
            self.revealOutputBox(autoHideAfter: 30)
        }
        agentRuntime.onAssistantResponseStarted = { [weak self] in
            guard let self, let runID = self.activeRequestID else { return }
            self.isCompactingContext = false
            self.streamTextCoalescer.reset()
            self.streamedResponse = ""
            self.hasReceivedStreamContent = false
            self.isExecutingCommand = false
            switch self.activeRequestKind {
            case .conversation:
                let messageID = UUID()
                self.activePetAssistantMessageID = messageID
                self.petDialogMessages.append(DialogMessage(
                    id: messageID,
                    role: .assistant,
                    content: ""
                ))
                self.stateCoordinator.send(.conversationStarted(runID))
            case .automation:
                self.stateCoordinator.send(.automationStarted(runID))
            case nil:
                return
            }
        }
        agentRuntime.onAssistantText = { [weak self] chunk in
            guard let self, let runID = self.activeRequestID, !chunk.isEmpty else { return }
            if !self.hasReceivedStreamContent {
                self.hasReceivedStreamContent = true
                switch self.activeRequestKind {
                case .conversation:
                    self.stateCoordinator.send(.conversationStreamStarted(runID))
                case .automation:
                    self.stateCoordinator.send(.automationStreamStarted(runID))
                case nil:
                    return
                }
            }
            self.streamTextCoalescer.append(chunk)
        }
        agentRuntime.onToolStarted = { [weak self] name in
            guard let self, let runID = self.activeRequestID else { return }
            self.streamTextCoalescer.flush()
            self.isExecutingCommand = true
            self.streamedResponse = "正在调用工具：\(name)…"
            if self.activeRequestKind == .conversation {
                self.fillEmptyPetAssistantMessage("正在调用工具：\(name)…")
            }
            self.revealOutputBox(autoHideAfter: 30)
            self.stateCoordinator.send(.commandStarted(runID))
        }
        agentRuntime.onToolFinished = { [weak self] name, result in
            guard let self else { return }
            self.isExecutingCommand = false
            self.isCompactingContext = false
            if result.isError {
                self.streamedResponse = "工具 \(name) 执行失败：\(result.content)"
                self.revealOutputBox(autoHideAfter: 15)
            }
        }
        agentRuntime.onApprovalRequested = { [weak self] approval in
            guard let self, let runID = self.activeRequestID else { return }
            self.streamTextCoalescer.flush()
            self.isExecutingCommand = false
            self.pendingCommand = approval.summary
            self.showCommandConfirm = true
            self.streamedResponse = "Agent 请求调用工具：\(approval.toolName)"
            self.revealOutputBox(autoHideAfter: 30)
            self.stateCoordinator.send(.commandConfirmationRequested(runID))
        }
        agentRuntime.onCompleted = { [weak self] in
            guard let self, let runID = self.activeRequestID else { return }
            self.streamTextCoalescer.flush()
            self.isExecutingCommand = false
            self.isCompactingContext = false
            let kind = self.activeRequestKind
            if self.streamedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.streamedResponse = "模型没有返回内容，需要你补充说明或重试。"
                switch kind {
                case .conversation:
                    self.stateCoordinator.send(.conversationNeedsInput(runID))
                case .automation:
                    self.stateCoordinator.send(.automationFailed(runID, "模型没有返回内容"))
                case nil:
                    return
                }
            } else {
                switch kind {
                case .conversation:
                    self.stateCoordinator.send(.conversationCompleted(runID))
                case .automation:
                    self.stateCoordinator.send(.automationCompleted(runID))
                case nil:
                    return
                }
            }
            self.revealOutputBox(autoHideAfter: self.configuredBubbleDuration)
            if kind == .conversation {
                self.fillEmptyPetAssistantMessage("（模型没有返回文本）")
                self.recordPetConversationAndScheduleExpiration()
            }
            self.activeRequestID = nil
            self.activeRequestKind = nil
            if kind == .conversation {
                self.schedulePetConversationExpiration()
            }
        }
        agentRuntime.onError = { [weak self] error in
            guard let self, let runID = self.activeRequestID else { return }
            self.streamTextCoalescer.reset()
            let message = error.localizedDescription
            self.isExecutingCommand = false
            self.isCompactingContext = false
            self.showCommandConfirm = false
            self.pendingCommand = ""
            self.streamedResponse = "请求失败：\(message)"
            if self.activeRequestKind == .conversation {
                self.fillEmptyPetAssistantMessage("请求失败：\(message)")
            }
            self.revealOutputBox(autoHideAfter: 15)
            let kind = self.activeRequestKind
            switch kind {
            case .conversation:
                self.stateCoordinator.send(.conversationFailed(runID, message))
            case .automation:
                self.stateCoordinator.send(.automationFailed(runID, message))
            case nil:
                return
            }
            if kind == .conversation {
                self.recordPetConversationAndScheduleExpiration()
            }
            self.activeRequestID = nil
            self.activeRequestKind = nil
            if kind == .conversation {
                self.schedulePetConversationExpiration()
            }
        }
    }

    private func appendStreamedResponse(_ text: String) {
        streamedResponseStore.append(text, limit: 5_000)
        guard activeRequestKind == .conversation,
              let messageID = activePetAssistantMessageID,
              let index = petDialogMessages.firstIndex(where: { $0.id == messageID }) else { return }
        petDialogMessages[index].content += text
    }

    private func fillEmptyPetAssistantMessage(_ text: String) {
        guard let messageID = activePetAssistantMessageID,
              let index = petDialogMessages.firstIndex(where: { $0.id == messageID }),
              petDialogMessages[index].content.isEmpty else { return }
        petDialogMessages[index].content = text
    }

    private func bindConversationStore() {
        conversationStore.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self, change.sourceID != self.conversationStoreSourceID else { return }
                self.handleConversationStoreChange(change.conversations)
            }
            .store(in: &cancellables)
    }

    private func handleConversationStoreChange(_ conversations: [DialogConversation]) {
        let storedPetConversation = conversations.first(where: { $0.kind == .pet })
        if activeRequestKind == .conversation {
            guard let petConversationID,
                  storedPetConversation?.id == petConversationID else {
                cancelPetConversationDeletedFromDialog()
                return
            }
            return
        }
        guard activeRequestID == nil else { return }

        guard let storedPetConversation else {
            clearPetConversationState()
            return
        }
        loadPetConversation(storedPetConversation)
        schedulePetConversationExpiration(at: .now)
    }

    private func cancelPetConversationDeletedFromDialog() {
        streamTextCoalescer.reset()
        agentRuntime.cancel()
        apiManager.cancelStreamRequest()
        activeRequestID = nil
        activeRequestKind = nil
        isRecognizingTrigger = false
        isCompactingContext = false
        isExecutingCommand = false
        showCommandConfirm = false
        pendingCommand = ""
        stateCoordinator.send(.resetToIdle)
        clearPetConversationState()
        streamedResponse = "桌宠会话已在完整模式中删除。"
        revealOutputBox(autoHideAfter: 6)
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

    private func bindCodexMonitor() {
        codexTaskMonitor.$lastEvent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleCodexEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleCodexEvent(_ event: CodexTaskMonitorEvent) {
        guard case .completed(let task) = event else { return }
        let announcement: String
        if let response = task.finalResponse, !response.isEmpty {
            announcement = "Codex 已完成「\(task.title)」：\n\n\(response)"
        } else {
            announcement = "Codex 已完成「\(task.title)」。"
        }

        guard activeRequestID == nil, !isRecognizingTrigger, !isExecutingCommand, !isCompactingContext else {
            pendingCodexAnnouncements.append(announcement)
            return
        }
        presentCodexAnnouncement(announcement)
    }

    private func showPendingCodexAnnouncementIfPossible() {
        guard activeRequestID == nil,
              !isRecognizingTrigger,
              !isExecutingCommand,
              !isCompactingContext,
              !pendingCodexAnnouncements.isEmpty else { return }
        presentCodexAnnouncement(pendingCodexAnnouncements.removeFirst())
    }

    private func presentCodexAnnouncement(_ message: String) {
        streamedResponse = message
        revealOutputBox(autoHideAfter: max(configuredBubbleDuration, 12))
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
        if !conversationStyle.staticMessages.isEmpty {
            streamedResponse = conversationStyle.staticMessages.randomElement() ?? ""
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

    private var configuredBubbleDuration: TimeInterval {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "bubbleAutoHideDuration") == nil
            ? 15
            : max(defaults.double(forKey: "bubbleAutoHideDuration"), 5)
    }

    private func restorePetConversationForNextInput(at date: Date = .now) {
        conversationExpirationTimer?.invalidate()
        conversationExpirationTimer = nil
        guard let storedConversation = conversationStore.petConversation else {
            clearPetConversationState()
            return
        }
        loadPetConversation(storedConversation)
        let history = petConversationSession.historyForNextInput(
            at: date,
            timeout: PetConversationRetention.timeout()
        )
        guard !history.isEmpty else {
            conversationStore.deleteConversation(
                storedConversation.id,
                sourceID: conversationStoreSourceID
            )
            clearPetConversationState()
            return
        }
        agentRuntime.restoreConversation(history)
    }

    private func recordPetConversationAndScheduleExpiration(at date: Date = .now) {
        persistPetConversation(at: date)
        schedulePetConversationExpiration(at: date)
    }

    private func persistPetConversation(at date: Date) {
        guard let petConversationID else { return }
        let existing = conversationStore.petConversation
        let createdAt = existing?.id == petConversationID
            ? (existing?.createdAt ?? date)
            : date
        let conversation = DialogConversation(
            id: petConversationID,
            title: "桌宠对话",
            messages: petDialogMessages,
            agentHistory: agentRuntime.messages,
            createdAt: createdAt,
            updatedAt: date,
            kind: .pet
        )
        petConversationSession.record(history: conversation.agentHistory, at: date)
        conversationStore.upsertPetConversation(conversation, sourceID: conversationStoreSourceID)
    }

    private func restorePersistedPetConversation(at date: Date = .now) {
        guard let conversation = conversationStore.petConversation else { return }
        loadPetConversation(conversation)
        petConversationSession.expireIfNeeded(
            at: date,
            timeout: PetConversationRetention.timeout()
        )
        if petConversationSession.isEmpty {
            conversationStore.deleteConversation(conversation.id, sourceID: conversationStoreSourceID)
            clearPetConversationState()
        } else {
            agentRuntime.restoreConversation(conversation.agentHistory)
            schedulePetConversationExpiration(at: date)
        }
    }

    private func loadPetConversation(_ conversation: DialogConversation) {
        petConversationID = conversation.id
        petDialogMessages = conversation.messages
        activePetAssistantMessageID = nil
        petConversationSession.destroy()
        petConversationSession.record(history: conversation.agentHistory, at: conversation.updatedAt)
        agentRuntime.restoreConversation(conversation.agentHistory)
    }

    private func schedulePetConversationExpiration(at date: Date = .now) {
        conversationExpirationTimer?.invalidate()
        conversationExpirationTimer = nil

        // A running foreground conversation owns the Runtime and resets the
        // inactivity clock when it finishes.
        guard activeRequestKind != .conversation else { return }
        let timeout = PetConversationRetention.timeout()
        petConversationSession.expireIfNeeded(at: date, timeout: timeout)
        guard let remaining = petConversationSession.remainingLifetime(at: date, timeout: timeout) else {
            clearRuntimeIfPetConversationExpired()
            return
        }
        guard remaining > 0 else {
            destroyPersistedPetConversation()
            return
        }

        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.expirePetConversationIfNeeded() }
        }
        timer.tolerance = min(max(remaining * 0.02, 1), 60)
        RunLoop.main.add(timer, forMode: .common)
        conversationExpirationTimer = timer
    }

    private func expirePetConversationIfNeeded(at date: Date = .now) {
        conversationExpirationTimer?.invalidate()
        conversationExpirationTimer = nil
        petConversationSession.expireIfNeeded(
            at: date,
            timeout: PetConversationRetention.timeout()
        )
        if petConversationSession.isEmpty {
            destroyPersistedPetConversation()
        } else {
            schedulePetConversationExpiration(at: date)
        }
    }

    private func destroyPersistedPetConversation() {
        if let petConversationID {
            conversationStore.deleteConversation(
                petConversationID,
                sourceID: conversationStoreSourceID
            )
        }
        clearPetConversationState()
    }

    private func clearPetConversationState() {
        conversationExpirationTimer?.invalidate()
        conversationExpirationTimer = nil
        petConversationSession.destroy()
        petConversationID = nil
        petDialogMessages = []
        activePetAssistantMessageID = nil
        clearRuntimeIfPetConversationExpired()
    }

    private func clearRuntimeIfPetConversationExpired() {
        guard petConversationSession.isEmpty, activeRequestID == nil else { return }
        agentRuntime.startNewConversation()
    }

    private var interactionDuration: TimeInterval? {
        guard let asset = currentCharacter.interactionAssets.first else { return nil }
        if let preferredDuration = asset.preferredDuration { return preferredDuration }
        guard asset.type.isAnimated, !asset.loop else { return nil }
        guard let cachedDuration = GIFDurationCalculator.cachedDuration(for: asset.location) else {
            GIFDurationCalculator.prefetchDuration(for: asset.location)
            return nil
        }
        return max(cachedDuration * 0.9, 0.5)
    }

    private func prefetchInteractionDurations() {
        for asset in currentCharacter.interactionAssets
        where asset.preferredDuration == nil && asset.type.isAnimated && !asset.loop {
            GIFDurationCalculator.prefetchDuration(for: asset.location)
        }
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
            Task { @MainActor in
                self?.refreshConversationStyle()
                self?.scheduleIdleSleepIfNeeded()
                self?.schedulePetConversationExpiration()
            }
        })
    }

    private func refreshConversationStyle() {
        conversationStyle = PetConversationStyleStore.style(for: currentCharacter.id)
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
