//
//  PetConversationRetention.swift
//  看板娘
//
//  桌宠气泡会话的上下文保留与过期策略。
//

import Foundation

enum PetConversationRetention {
    static let storageKey = "petConversationRetentionMinutes"
    static let defaultMinutes: Double = 30
    static let minimumMinutes: Double = 5
    static let maximumMinutes: Double = 24 * 60
    static let stepMinutes: Double = 5

    static func minutes(in defaults: UserDefaults = .standard) -> Double {
        minutes(storedValue: defaults.object(forKey: storageKey) as? NSNumber)
    }

    static func minutes(storedValue: NSNumber?) -> Double {
        guard let storedValue else { return defaultMinutes }
        return normalized(storedValue.doubleValue)
    }

    static func timeout(in defaults: UserDefaults = .standard) -> TimeInterval? {
        let minutes = minutes(in: defaults)
        return minutes == 0 ? nil : minutes * 60
    }

    static func normalized(_ minutes: Double) -> Double {
        guard minutes.isFinite, minutes != 0 else { return 0 }
        let clamped = min(max(minutes, minimumMinutes), maximumMinutes)
        return (clamped / stepMinutes).rounded() * stepMinutes
    }

    static func description(for minutes: Double) -> String {
        let normalizedMinutes = normalized(minutes)
        guard normalizedMinutes > 0 else { return "不销毁" }
        let totalMinutes = Int(normalizedMinutes)
        if totalMinutes < 60 {
            return "\(totalMinutes) 分钟"
        }
        if totalMinutes.isMultiple(of: 60) {
            return "\(totalMinutes / 60) 小时"
        }
        return "\(totalMinutes / 60) 小时 \(totalMinutes % 60) 分钟"
    }
}
