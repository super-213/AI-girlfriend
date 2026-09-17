//
//  PetVisualState.swift
//  看板娘
//
//  桌宠运行状态、事件与可恢复快照。
//

import Combine
import Foundation

enum PetActivityState: String, Codable, CaseIterable, Identifiable {
    case idle
    case thinking
    case talking
    case working
    case waitingForConfirmation
    case success
    case error
    case sleeping
    case needsInput
    case listening
    case playingAudio
    case automation
    case triggered

    var id: String { rawValue }

    var priority: Int {
        switch self {
        case .waitingForConfirmation: return 100
        case .error: return 90
        case .needsInput: return 80
        case .working: return 70
        case .automation, .triggered: return 68
        case .playingAudio: return 65
        case .talking: return 60
        case .thinking: return 50
        case .listening: return 40
        case .success: return 30
        case .idle: return 10
        case .sleeping: return 0
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "待命中"
        case .thinking: return "思考中"
        case .talking: return "回复中"
        case .working: return "执行中"
        case .waitingForConfirmation: return "等待确认"
        case .success: return "已完成"
        case .error: return "出错了"
        case .sleeping: return "休息中"
        case .needsInput: return "需要补充"
        case .listening: return "正在倾听"
        case .playingAudio: return "播放中"
        case .automation: return "自动化运行中"
        case .triggered: return "已命中触发器"
        }
    }

    var systemImage: String {
        switch self {
        case .idle: return "circle.fill"
        case .thinking: return "ellipsis"
        case .talking: return "text.bubble.fill"
        case .working: return "hammer.fill"
        case .waitingForConfirmation: return "exclamationmark.shield.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .sleeping: return "moon.zzz.fill"
        case .needsInput: return "questionmark.bubble.fill"
        case .listening: return "ear.fill"
        case .playingAudio: return "speaker.wave.2.fill"
        case .automation: return "clock.arrow.circlepath"
        case .triggered: return "bolt.fill"
        }
    }
}

enum PetStateSource: String, Codable, Equatable {
    case system
    case conversation
    case command
    case automation
    case trigger
    case audio
    case userInteraction
    case companion
}

enum PetTransientEffect: String, Codable, Equatable {
    case clicked
    case greet
    case success
    case errorPulse
    case attention

    var renderedState: PetActivityState? {
        switch self {
        case .success: return .success
        case .errorPulse: return .error
        case .clicked, .greet, .attention: return nil
        }
    }

    var priority: Int {
        switch self {
        case .errorPulse: return PetActivityState.error.priority
        case .attention: return 75
        case .success: return PetActivityState.success.priority
        case .clicked, .greet: return 20
        }
    }
}

struct PetStateSnapshot: Codable, Equatable {
    var activityState: PetActivityState
    var renderedState: PetActivityState
    var source: PetStateSource
    var runID: UUID?
    var startedAt: Date
    var hasPendingConfirmation: Bool

    static func idle(at date: Date = Date()) -> PetStateSnapshot {
        PetStateSnapshot(
            activityState: .idle,
            renderedState: .idle,
            source: .system,
            runID: nil,
            startedAt: date,
            hasPendingConfirmation: false
        )
    }
}

enum PetStateEvent: Equatable {
    case conversationStarted(UUID)
    case conversationStreamStarted(UUID)
    case conversationCompleted(UUID)
    case conversationFailed(UUID, String)
    case conversationNeedsInput(UUID)
    case commandConfirmationRequested(UUID)
    case commandStarted(UUID)
    case commandCompleted(UUID)
    case commandFailed(UUID, String)
    case automationStarted(UUID)
    case automationStreamStarted(UUID)
    case automationCompleted(UUID)
    case automationFailed(UUID, String)
    case triggerMatched(UUID)
    case triggerStarted(UUID)
    case triggerCompleted(UUID)
    case triggerFailed(UUID, String)
    case audioStarted(UUID)
    case audioCompleted(UUID)
    case listeningChanged(Bool)
    case interaction(PetTransientEffect, TimeInterval?)
    case idleTimeoutReached
    case resetToIdle
}

/// 所有业务流程只向该协调器发送结构化事件；View 只读取快照。
@MainActor
final class PetStateCoordinator: ObservableObject {
    @Published private(set) var snapshot: PetStateSnapshot
    @Published private(set) var transientEffect: PetTransientEffect?
    @Published private(set) var lastErrorMessage: String?

    private var effectGeneration = UUID()
    private var stateGeneration = UUID()
    private var transientExpiresAt: Date?

    init(now: Date = Date()) {
        snapshot = .idle(at: now)
    }

    var isBusy: Bool {
        switch snapshot.activityState {
        case .thinking, .talking, .working, .waitingForConfirmation, .automation, .triggered:
            return true
        default:
            return false
        }
    }

    func send(_ event: PetStateEvent, at date: Date = Date()) {
        switch event {
        case .conversationStarted(let id):
            setActivity(.thinking, source: .conversation, runID: id, at: date, startsNewRun: true)
        case .conversationStreamStarted(let id):
            setActivityIfCurrent(.talking, source: .conversation, runID: id, at: date)
        case .conversationCompleted(let id):
            completeIfCurrent(runID: id, source: .conversation, at: date)
        case .conversationFailed(let id, let message):
            failIfCurrent(runID: id, source: .conversation, message: message, at: date)
        case .conversationNeedsInput(let id):
            setActivityIfCurrent(.needsInput, source: .conversation, runID: id, at: date)
        case .commandConfirmationRequested(let id):
            setActivityIfCurrent(.waitingForConfirmation, source: .command, runID: id, at: date)
        case .commandStarted(let id):
            setActivityIfCurrent(.working, source: .command, runID: id, at: date)
        case .commandCompleted(let id):
            completeIfCurrent(runID: id, source: .command, at: date)
        case .commandFailed(let id, let message):
            failIfCurrent(runID: id, source: .command, message: message, at: date)
        case .automationStarted(let id):
            setActivity(.automation, source: .automation, runID: id, at: date, startsNewRun: true)
        case .automationStreamStarted(let id):
            setActivityIfCurrent(.talking, source: .automation, runID: id, at: date)
        case .automationCompleted(let id):
            completeIfCurrent(runID: id, source: .automation, at: date)
        case .automationFailed(let id, let message):
            failIfCurrent(runID: id, source: .automation, message: message, at: date)
        case .triggerMatched(let id):
            setActivity(.triggered, source: .trigger, runID: id, at: date, startsNewRun: snapshot.runID != id)
        case .triggerStarted(let id):
            setActivity(.working, source: .trigger, runID: id, at: date, startsNewRun: snapshot.runID != id)
        case .triggerCompleted(let id):
            completeIfCurrent(runID: id, source: .trigger, at: date)
        case .triggerFailed(let id, let message):
            failIfCurrent(runID: id, source: .trigger, message: message, at: date)
        case .audioStarted(let id):
            guard snapshot.source == .trigger || snapshot.source == .automation || snapshot.activityState == .idle else {
                return
            }
            setActivity(.playingAudio, source: .audio, runID: id, at: date, startsNewRun: false)
        case .audioCompleted(let id):
            completeIfCurrent(runID: id, source: .audio, at: date)
        case .listeningChanged(let isListening):
            updateListening(isListening, at: date)
        case .interaction(let effect, let preferredDuration):
            showTransient(effect, duration: preferredDuration ?? (effect == .clicked ? 1.8 : 2.2), at: date)
        case .idleTimeoutReached:
            guard snapshot.activityState == .idle else { return }
            setActivity(.sleeping, source: .system, runID: nil, at: date, startsNewRun: true)
        case .resetToIdle:
            resetToIdle(at: date)
        }
    }

    /// 供确定性的单元测试和应用恢复时主动结算短暂效果。
    func expireTransientEffect(at date: Date = Date()) {
        guard let transientExpiresAt, date >= transientExpiresAt else { return }
        self.transientEffect = nil
        self.transientExpiresAt = nil
        recomputeRenderedState()
    }

    private func setActivity(
        _ state: PetActivityState,
        source: PetStateSource,
        runID: UUID?,
        at date: Date,
        startsNewRun: Bool
    ) {
        if snapshot.activityState == .waitingForConfirmation,
           snapshot.runID != runID,
           state != .error {
            return
        }

        if startsNewRun,
           snapshot.isProtectedForegroundTask,
           snapshot.runID != runID,
           state.priority <= snapshot.activityState.priority {
            return
        }

        snapshot.activityState = state
        snapshot.source = source
        snapshot.runID = runID
        snapshot.startedAt = date
        snapshot.hasPendingConfirmation = state == .waitingForConfirmation
        lastErrorMessage = nil

        if let transientEffect, state.priority > transientEffect.priority {
            clearTransient()
        }
        recomputeRenderedState()
    }

    private func setActivityIfCurrent(
        _ state: PetActivityState,
        source: PetStateSource,
        runID: UUID,
        at date: Date
    ) {
        guard snapshot.runID == runID else { return }
        setActivity(state, source: source, runID: runID, at: date, startsNewRun: false)
    }

    private func completeIfCurrent(runID: UUID, source: PetStateSource, at date: Date) {
        guard snapshot.runID == runID else { return }
        snapshot = PetStateSnapshot(
            activityState: .idle,
            renderedState: .idle,
            source: source,
            runID: nil,
            startedAt: date,
            hasPendingConfirmation: false
        )
        showTransient(.success, duration: 2.4, at: date)
    }

    private func failIfCurrent(runID: UUID, source: PetStateSource, message: String, at date: Date) {
        guard snapshot.runID == runID else { return }
        setActivity(.error, source: source, runID: runID, at: date, startsNewRun: false)
        lastErrorMessage = message
        showTransient(.errorPulse, duration: 2.0, at: date)

        let generation = UUID()
        stateGeneration = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.stateGeneration == generation,
                  self.snapshot.runID == runID,
                  self.snapshot.activityState == .error else { return }
            self.resetToIdle(at: Date())
        }
    }

    private func updateListening(_ isListening: Bool, at date: Date) {
        if isListening {
            guard snapshot.activityState == .idle || snapshot.activityState == .sleeping else { return }
            setActivity(.listening, source: .userInteraction, runID: nil, at: date, startsNewRun: true)
        } else if snapshot.activityState == .listening {
            resetToIdle(at: date)
        }
    }

    private func showTransient(_ effect: PetTransientEffect, duration: TimeInterval, at date: Date) {
        if snapshot.activityState.priority > effect.priority {
            return
        }

        transientEffect = effect
        transientExpiresAt = date.addingTimeInterval(duration)
        recomputeRenderedState()

        let generation = UUID()
        effectGeneration = generation
        Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, self.effectGeneration == generation else { return }
            self.expireTransientEffect(at: Date())
        }
    }

    private func clearTransient() {
        effectGeneration = UUID()
        transientEffect = nil
        transientExpiresAt = nil
    }

    private func resetToIdle(at date: Date) {
        stateGeneration = UUID()
        clearTransient()
        snapshot = .idle(at: date)
    }

    private func recomputeRenderedState() {
        if let effectState = transientEffect?.renderedState,
           effectState.priority >= snapshot.activityState.priority {
            snapshot.renderedState = effectState
        } else {
            snapshot.renderedState = snapshot.activityState
        }
    }
}

private extension PetStateSnapshot {
    var isProtectedForegroundTask: Bool {
        switch activityState {
        case .waitingForConfirmation, .working, .talking, .thinking:
            return true
        default:
            return false
        }
    }
}
