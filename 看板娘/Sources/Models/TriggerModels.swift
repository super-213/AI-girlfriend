//
//  TriggerModels.swift
//  桌面宠物应用
//
//  触发器配置、运行记录和运行状态模型
//

import Foundation

enum TriggerActionType: String, Codable, CaseIterable, Identifiable {
    case playAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playAudio:
            return "播放音频"
        }
    }
}

enum TriggerMatchType: String, Codable {
    case start
    case stop
}

enum TriggerRuntimeStatus: String, Codable, CaseIterable {
    case disabled
    case idle
    case recognizing
    case triggered
    case executing
    case succeeded
    case failed
    case terminated

    var title: String {
        switch self {
        case .disabled: return "未启用"
        case .idle: return "待触发"
        case .recognizing: return "识别中"
        case .triggered: return "已触发"
        case .executing: return "执行中"
        case .succeeded: return "执行成功"
        case .failed: return "执行失败"
        case .terminated: return "已终止"
        }
    }
}

struct TriggerActionConfiguration: Codable, Equatable {
    var type: TriggerActionType
    var audioBookmarkData: Data?
    var audioFileName: String?
    var audioFilePath: String?

    static let defaultMP3 = TriggerActionConfiguration(
        type: .playAudio,
        audioBookmarkData: nil,
        audioFileName: nil,
        audioFilePath: nil
    )
}

struct TriggerDefinition: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var isEnabled: Bool
    var inputDescription: String
    var startKeyword: String
    var action: TriggerActionConfiguration
    var stopInputDescription: String
    var stopKeyword: String
    var createdAt: Date
    var updatedAt: Date

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名触发器" : trimmed
    }

    var hasRunnableAction: Bool {
        switch action.type {
        case .playAudio:
            return action.audioBookmarkData != nil
        }
    }

    static func makeDefault(now: Date = Date()) -> TriggerDefinition {
        let id = UUID()
        return TriggerDefinition(
            id: id,
            title: "新的触发器",
            isEnabled: true,
            inputDescription: "",
            startKeyword: Self.keyword(prefix: "TRIGGER_PLAY_MP3", id: id),
            action: .defaultMP3,
            stopInputDescription: "识别用户是否想暂停、停止、终止、取消当前音频播放。",
            stopKeyword: Self.keyword(prefix: "TRIGGER_STOP_MP3", id: id),
            createdAt: now,
            updatedAt: now
        )
    }

    private static func keyword(prefix: String, id: UUID) -> String {
        "\(prefix)_\(id.uuidString.prefix(8).uppercased())"
    }
}

struct TriggerRun: Codable, Identifiable, Equatable {
    var id: UUID
    var triggerId: UUID
    var type: TriggerMatchType
    var startedAt: Date
    var endedAt: Date?
    var status: TriggerRuntimeStatus
    var errorMessage: String?
}

struct TriggerRuntimeState: Codable, Equatable {
    var triggerId: UUID
    var status: TriggerRuntimeStatus
    var currentRunId: UUID?
    var startedAt: Date?
    var endedAt: Date?
    var lastErrorMessage: String?

    static func idle(triggerId: UUID, isEnabled: Bool) -> TriggerRuntimeState {
        TriggerRuntimeState(
            triggerId: triggerId,
            status: isEnabled ? .idle : .disabled,
            currentRunId: nil,
            startedAt: nil,
            endedAt: nil,
            lastErrorMessage: nil
        )
    }
}

struct TriggerRecognitionResult: Decodable, Equatable {
    var matched: Bool
    var triggerId: UUID?
    var keyword: String?
    var type: TriggerMatchType?
}

enum TriggerStorageKeys {
    static let definitions = "triggerDefinitions"
}
