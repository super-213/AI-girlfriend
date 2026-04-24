//
//  PetControlService.swift
//  看板娘
//
//  Stable machine-callable control surface for app actions.
//

import Foundation

enum PetControlActionSource: String, Codable {
    case ui
    case appIntent
    case shortcut
    case urlScheme
    case localHTTP
    case websocket
    case mcp
    case automation
    case unknown
}

struct PetControlRequestContext: Codable {
    var requestID: UUID
    var source: PetControlActionSource
    var actorID: String
    var requiresUserConfirmation: Bool
    var createdAt: Date

    init(
        requestID: UUID = UUID(),
        source: PetControlActionSource = .ui,
        actorID: String = "local-user",
        requiresUserConfirmation: Bool = false,
        createdAt: Date = Date()
    ) {
        self.requestID = requestID
        self.source = source
        self.actorID = actorID
        self.requiresUserConfirmation = requiresUserConfirmation
        self.createdAt = createdAt
    }
}

enum PetControlErrorCode: String, Codable {
    case invalidInput
    case notFound
    case busy
    case permissionDenied
    case validationFailed
    case unavailable
    case internalError
}

struct PetControlError: Error, Codable, LocalizedError {
    let code: PetControlErrorCode
    let message: String

    var errorDescription: String? { message }

    static func invalidInput(_ message: String) -> PetControlError {
        PetControlError(code: .invalidInput, message: message)
    }

    static func notFound(_ message: String) -> PetControlError {
        PetControlError(code: .notFound, message: message)
    }

    static func busy(_ message: String) -> PetControlError {
        PetControlError(code: .busy, message: message)
    }

    static func unavailable(_ message: String) -> PetControlError {
        PetControlError(code: .unavailable, message: message)
    }

    static func internalError(_ message: String) -> PetControlError {
        PetControlError(code: .internalError, message: message)
    }
}

struct PetRuntimeStateSnapshot: Codable, Equatable {
    var currentCharacterName: String
    var currentGif: String
    var isThinking: Bool
    var isExecutingCommand: Bool
    var streamedResponse: String
}

struct SendMessageRequest: Codable {
    var text: String
    var context: PetControlRequestContext

    init(text: String, context: PetControlRequestContext = PetControlRequestContext()) {
        self.text = text
        self.context = context
    }
}

struct SendMessageResult: Codable {
    var requestID: UUID
    var accepted: Bool
    var state: PetRuntimeStateSnapshot
}

struct CharacterDTO: Codable, Identifiable, Equatable {
    var id: String
    var index: Int
    var name: String
    var normalGif: String
    var clickGif: String
    var isCustom: Bool
}

struct SwitchCharacterRequest: Codable {
    var index: Int?
    var name: String?
    var context: PetControlRequestContext

    init(index: Int? = nil, name: String? = nil, context: PetControlRequestContext = PetControlRequestContext()) {
        self.index = index
        self.name = name
        self.context = context
    }
}

struct SkillDTO: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var addedAt: Date
}

struct ImportSkillRequest: Codable {
    var filePath: String
    var displayName: String?
    var context: PetControlRequestContext

    init(filePath: String, displayName: String? = nil, context: PetControlRequestContext = PetControlRequestContext()) {
        self.filePath = filePath
        self.displayName = displayName
        self.context = context
    }
}

struct AutomationDTO: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var prompt: String
    var frequency: AutomationFrequency
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastRunAt: Date?
    var nextRunAt: Date?
}

struct UpdateAutomationRequest: Codable {
    var id: UUID
    var title: String?
    var prompt: String?
    var frequency: AutomationFrequency?
    var isEnabled: Bool?
    var context: PetControlRequestContext

    init(
        id: UUID,
        title: String? = nil,
        prompt: String? = nil,
        frequency: AutomationFrequency? = nil,
        isEnabled: Bool? = nil,
        context: PetControlRequestContext = PetControlRequestContext()
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.frequency = frequency
        self.isEnabled = isEnabled
        self.context = context
    }
}

struct RunAutomationRequest: Codable {
    var id: UUID?
    var prompt: String?
    var context: PetControlRequestContext

    init(id: UUID? = nil, prompt: String? = nil, context: PetControlRequestContext = PetControlRequestContext(source: .automation)) {
        self.id = id
        self.prompt = prompt
        self.context = context
    }
}

struct AutomationRunResult: Codable {
    var requestID: UUID
    var automationID: UUID?
    var accepted: Bool
    var state: PetRuntimeStateSnapshot
}

struct SettingsPatch: Codable {
    var apiKey: String?
    var apiUrl: String?
    var aiModel: String?
    var provider: String?
    var systemPrompt: String?
    var overlapRatio: Double?
    var staticMessages: [String]?
    var context: PetControlRequestContext

    init(
        apiKey: String? = nil,
        apiUrl: String? = nil,
        aiModel: String? = nil,
        provider: String? = nil,
        systemPrompt: String? = nil,
        overlapRatio: Double? = nil,
        staticMessages: [String]? = nil,
        context: PetControlRequestContext = PetControlRequestContext()
    ) {
        self.apiKey = apiKey
        self.apiUrl = apiUrl
        self.aiModel = aiModel
        self.provider = provider
        self.systemPrompt = systemPrompt
        self.overlapRatio = overlapRatio
        self.staticMessages = staticMessages
        self.context = context
    }
}

struct SettingsSnapshot: Codable, Equatable {
    var apiUrl: String
    var aiModel: String
    var provider: String
    var systemPrompt: String
    var overlapRatio: Double
    var staticMessages: [String]
}

private struct PetControlAuditEvent: Codable {
    var id: UUID
    var action: String
    var requestID: UUID
    var source: PetControlActionSource
    var actorID: String
    var status: String
    var message: String
    var createdAt: Date
}

protocol PetControlling: AnyObject {
    func sendMessage(_ request: SendMessageRequest) throws -> SendMessageResult
    func switchCharacter(_ request: SwitchCharacterRequest) throws -> CharacterDTO
    func listCharacters(context: PetControlRequestContext) -> [CharacterDTO]
    func listAutomations(context: PetControlRequestContext) -> [AutomationDTO]
    func updateAutomation(_ request: UpdateAutomationRequest) throws -> AutomationDTO
    func runAutomation(_ request: RunAutomationRequest) throws -> AutomationRunResult
    func updateSettings(_ patch: SettingsPatch) throws -> SettingsSnapshot
    func importSkill(_ request: ImportSkillRequest) throws -> SkillDTO
}

final class PetControlService: PetControlling {
    static let shared = PetControlService()

    private weak var petViewBackend: PetViewBackend?
    private let automationStore: AutomationStore
    private let defaults: UserDefaults
    private let auditLogger = PetControlAuditLogger()

    private init(automationStore: AutomationStore = .shared, defaults: UserDefaults = .standard) {
        self.automationStore = automationStore
        self.defaults = defaults
    }

    func register(petViewBackend: PetViewBackend) {
        self.petViewBackend = petViewBackend
    }

    func sendMessage(_ request: SendMessageRequest) throws -> SendMessageResult {
        do {
            let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw PetControlError.invalidInput("消息内容不能为空")
            }
            let backend = try requireBackend()
            guard !backend.isThinking, !backend.isExecutingCommand else {
                throw PetControlError.busy("当前正在处理请求，稍后再试")
            }

            backend.submitExternalInput(text)
            let result = SendMessageResult(
                requestID: request.context.requestID,
                accepted: true,
                state: snapshot(from: backend)
            )
            audit("sendMessage", context: request.context, status: "accepted", message: text)
            return result
        } catch {
            audit("sendMessage", context: request.context, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    func switchCharacter(_ request: SwitchCharacterRequest) throws -> CharacterDTO {
        do {
            let backend = try requireBackend()
            let characters = listCharacters(context: request.context)
            let target: CharacterDTO?

            if let index = request.index {
                target = characters.first { $0.index == index }
            } else if let name = request.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                target = characters.first { $0.name == name || $0.id == name }
            } else {
                throw PetControlError.invalidInput("必须提供角色 index 或 name")
            }

            guard let target else {
                throw PetControlError.notFound("未找到指定角色")
            }

            let character = allCharacters()[target.index]
            backend.switchToCharacter(character)
            audit("switchCharacter", context: request.context, status: "accepted", message: target.name)
            return target
        } catch {
            audit("switchCharacter", context: request.context, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    func listCharacters(context: PetControlRequestContext = PetControlRequestContext()) -> [CharacterDTO] {
        allCharacters().enumerated().map { index, character in
            CharacterDTO(
                id: character.name,
                index: index,
                name: character.name,
                normalGif: character.normalGif,
                clickGif: character.clickGif,
                isCustom: index >= availableCharacters.count
            )
        }
    }

    func listAutomations(context: PetControlRequestContext = PetControlRequestContext()) -> [AutomationDTO] {
        let automations = automationStore.automations.map(AutomationDTO.init(flow:))
        audit("listAutomations", context: context, status: "accepted", message: "\(automations.count)")
        return automations
    }

    func updateAutomation(_ request: UpdateAutomationRequest) throws -> AutomationDTO {
        do {
            guard var automation = automationStore.automation(id: request.id) else {
                throw PetControlError.notFound("未找到指定自动化")
            }

            if let title = request.title {
                automation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let prompt = request.prompt {
                automation.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let frequency = request.frequency {
                automation.frequency = frequency
            }
            if let isEnabled = request.isEnabled {
                automation.isEnabled = isEnabled
            }

            guard !automation.normalizedTitle.isEmpty else {
                throw PetControlError.invalidInput("自动化标题不能为空")
            }

            automationStore.updateAutomation(automation)
            guard let updated = automationStore.automation(id: request.id) else {
                throw PetControlError.internalError("自动化更新后无法读取")
            }
            audit("updateAutomation", context: request.context, status: "accepted", message: updated.normalizedTitle)
            return AutomationDTO(flow: updated)
        } catch {
            audit("updateAutomation", context: request.context, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    func runAutomation(_ request: RunAutomationRequest) throws -> AutomationRunResult {
        do {
            let backend = try requireBackend()
            guard !backend.isThinking, !backend.isExecutingCommand else {
                throw PetControlError.busy("当前正在处理请求，稍后再试")
            }

            let prompt: String
            var automationID: UUID?

            if let id = request.id {
                guard let automation = automationStore.automation(id: id) else {
                    throw PetControlError.notFound("未找到指定自动化")
                }
                prompt = automation.prompt
                automationID = automation.id
                automationStore.markCompleted(automation)
            } else if let requestPrompt = request.prompt {
                prompt = requestPrompt
            } else {
                throw PetControlError.invalidInput("必须提供自动化 id 或 prompt")
            }

            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPrompt.isEmpty else {
                throw PetControlError.invalidInput("自动化提示词不能为空")
            }

            backend.submitExternalInput(trimmedPrompt)
            let result = AutomationRunResult(
                requestID: request.context.requestID,
                automationID: automationID,
                accepted: true,
                state: snapshot(from: backend)
            )
            audit("runAutomation", context: request.context, status: "accepted", message: automationID?.uuidString ?? "ad-hoc")
            return result
        } catch {
            audit("runAutomation", context: request.context, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    func updateSettings(_ patch: SettingsPatch) throws -> SettingsSnapshot {
        do {
            if let apiKey = patch.apiKey {
                defaults.set(apiKey, forKey: "apiKey")
            }
            if let apiUrl = patch.apiUrl {
                guard URL(string: apiUrl) != nil else {
                    throw PetControlError.invalidInput("API URL 格式无效")
                }
                defaults.set(apiUrl, forKey: "apiUrl")
            }
            if let aiModel = patch.aiModel {
                let trimmed = aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw PetControlError.invalidInput("模型名称不能为空")
                }
                defaults.set(trimmed, forKey: "aiModel")
            }
            if let provider = patch.provider {
                let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard ["zhipu", "qwen", "ollama"].contains(normalized) else {
                    throw PetControlError.invalidInput("不支持的 provider: \(provider)")
                }
                defaults.set(normalized, forKey: "provider")
            }
            if let systemPrompt = patch.systemPrompt {
                defaults.set(systemPrompt, forKey: "systemPrompt")
            }
            if let overlapRatio = patch.overlapRatio {
                guard (0...1).contains(overlapRatio) else {
                    throw PetControlError.invalidInput("overlapRatio 必须在 0 到 1 之间")
                }
                defaults.set(overlapRatio, forKey: "overlapRatio")
            }
            if let staticMessages = patch.staticMessages {
                let data = try JSONEncoder().encode(staticMessages)
                defaults.set(data, forKey: "staticMessages")
            }

            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
            let snapshot = settingsSnapshot()
            audit("updateSettings", context: patch.context, status: "accepted", message: snapshot.provider)
            return snapshot
        } catch {
            audit("updateSettings", context: patch.context, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    func importSkill(_ request: ImportSkillRequest) throws -> SkillDTO {
        do {
            let source = URL(fileURLWithPath: request.filePath)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw PetControlError.notFound("skill 文件不存在")
            }
            guard source.pathExtension.lowercased() == "md" else {
                throw PetControlError.invalidInput("skill 文件必须是 .md")
            }

            let destination = try copySkillFile(from: source, displayName: request.displayName)
            var saved = loadSkillFiles()
            let skill = SkillFile(
                id: UUID(),
                name: destination.lastPathComponent,
                path: destination.path,
                addedAt: Date()
            )
            saved.append(skill)
            saveSkillFiles(saved)

            let dto = SkillDTO(skill: skill)
            audit("importSkill", context: request.context, status: "accepted", message: dto.name)
            return dto
        } catch {
            audit("importSkill", context: request.context, status: "failed", message: error.localizedDescription)
            throw error
        }
    }

    func importSkills(from urls: [URL], context: PetControlRequestContext = PetControlRequestContext()) -> [SkillFile] {
        var imported: [SkillFile] = []
        for url in urls {
            do {
                let dto = try importSkill(ImportSkillRequest(filePath: url.path, context: context))
                imported.append(SkillFile(id: dto.id, name: dto.name, path: dto.path, addedAt: dto.addedAt))
            } catch {
                audit("importSkill", context: context, status: "failed", message: error.localizedDescription)
            }
        }
        return imported
    }

    private func requireBackend() throws -> PetViewBackend {
        guard let petViewBackend else {
            throw PetControlError.unavailable("宠物控制后端尚未注册")
        }
        return petViewBackend
    }

    private func snapshot(from backend: PetViewBackend) -> PetRuntimeStateSnapshot {
        PetRuntimeStateSnapshot(
            currentCharacterName: backend.currentCharacter.name,
            currentGif: backend.currentGif,
            isThinking: backend.isThinking,
            isExecutingCommand: backend.isExecutingCommand,
            streamedResponse: backend.streamedResponse
        )
    }

    private func allCharacters() -> [PetCharacter] {
        var characters = availableCharacters
        characters.append(contentsOf: loadCustomCharacters())
        return characters
    }

    private func loadCustomCharacters() -> [PetCharacter] {
        guard let data = defaults.data(forKey: "customCharacters"),
              let characters = try? JSONDecoder().decode([PetCharacter].self, from: data) else {
            return []
        }
        return characters
    }

    private func settingsSnapshot() -> SettingsSnapshot {
        var staticMessages: [String] = []
        if let data = defaults.data(forKey: "staticMessages"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            staticMessages = decoded
        }

        return SettingsSnapshot(
            apiUrl: defaults.string(forKey: "apiUrl") ?? "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            aiModel: defaults.string(forKey: "aiModel") ?? "glm-4v-flash",
            provider: defaults.string(forKey: "provider") ?? "zhipu",
            systemPrompt: defaults.string(forKey: "systemPrompt") ?? "",
            overlapRatio: defaults.object(forKey: "overlapRatio") == nil ? 0.3 : defaults.double(forKey: "overlapRatio"),
            staticMessages: staticMessages
        )
    }

    private func copySkillFile(from source: URL, displayName: String?) throws -> URL {
        let agentDir = try agentSkillsDirectory()
        let fileManager = FileManager.default
        let rawBaseName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? displayName!
            : source.deletingPathExtension().lastPathComponent
        let safeName = rawBaseName.isEmpty ? "skill" : rawBaseName
        var destination = agentDir.appendingPathComponent("\(safeName).md")

        if fileManager.fileExists(atPath: destination.path) {
            let timestamp = Int(Date().timeIntervalSince1970)
            destination = agentDir.appendingPathComponent("\(safeName)_\(timestamp).md")
        }

        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    private func agentSkillsDirectory() throws -> URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PetControlError.unavailable("无法访问应用支持目录")
        }
        let appDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "PetApp")
        let agentSkillsURL = appDirectory.appendingPathComponent("AgentSkills")
        if !fileManager.fileExists(atPath: agentSkillsURL.path) {
            try fileManager.createDirectory(at: agentSkillsURL, withIntermediateDirectories: true)
        }
        return agentSkillsURL
    }

    private func loadSkillFiles() -> [SkillFile] {
        guard let data = defaults.data(forKey: AgentSkillStorageKeys.skillFiles),
              let saved = try? JSONDecoder().decode([SkillFile].self, from: data) else {
            return []
        }
        return saved
    }

    private func saveSkillFiles(_ skillFiles: [SkillFile]) {
        if let data = try? JSONEncoder().encode(skillFiles) {
            defaults.set(data, forKey: AgentSkillStorageKeys.skillFiles)
        }
    }

    private func audit(_ action: String, context: PetControlRequestContext, status: String, message: String) {
        let event = PetControlAuditEvent(
            id: UUID(),
            action: action,
            requestID: context.requestID,
            source: context.source,
            actorID: context.actorID,
            status: status,
            message: message,
            createdAt: Date()
        )
        auditLogger.append(event)
    }
}

private extension AutomationDTO {
    init(flow: AutomationFlow) {
        self.init(
            id: flow.id,
            title: flow.normalizedTitle,
            prompt: flow.prompt,
            frequency: flow.frequency,
            isEnabled: flow.isEnabled,
            createdAt: flow.createdAt,
            updatedAt: flow.updatedAt,
            lastRunAt: flow.lastRunAt,
            nextRunAt: flow.nextRunAt
        )
    }
}

private extension SkillDTO {
    init(skill: SkillFile) {
        self.init(id: skill.id, name: skill.name, path: skill.path, addedAt: skill.addedAt)
    }
}

private final class PetControlAuditLogger {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func append(_ event: PetControlAuditEvent) {
        do {
            let url = try auditLogURL()
            let data = try encoder.encode(event)
            guard var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let lineData = line.data(using: .utf8) {
                    try handle.write(contentsOf: lineData)
                }
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            #if DEBUG
            print("PetControl audit failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func auditLogURL() throws -> URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PetControlError.unavailable("无法访问应用支持目录")
        }
        let appDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "PetApp")
        let auditDirectory = appDirectory.appendingPathComponent("AuditLogs")
        if !fileManager.fileExists(atPath: auditDirectory.path) {
            try fileManager.createDirectory(at: auditDirectory, withIntermediateDirectories: true)
        }
        return auditDirectory.appendingPathComponent("pet-control.jsonl")
    }
}
