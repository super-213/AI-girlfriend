//
//  AutomationModels.swift
//  桌面宠物应用
//
//  自动化流程的数据模型
//

import Foundation

enum AutomationFrequency: Codable, Equatable, Hashable {
    case runOnce
    case every15Minutes
    case hourly
    case daily
    case everyNDays(Int)
    case weekly
    case monthly
    case yearly

    enum Kind: String, Codable, CaseIterable, Identifiable {
        case runOnce
        case every15Minutes
        case hourly
        case daily
        case everyNDays
        case weekly
        case monthly
        case yearly

        var id: String { rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case dayInterval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .runOnce:
            self = .runOnce
        case .every15Minutes:
            self = .every15Minutes
        case .hourly:
            self = .hourly
        case .daily:
            self = .daily
        case .everyNDays:
            let interval = try container.decodeIfPresent(Int.self, forKey: .dayInterval) ?? 2
            self = .everyNDays(Self.clampedDayInterval(interval))
        case .weekly:
            self = .weekly
        case .monthly:
            self = .monthly
        case .yearly:
            self = .yearly
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if case let .everyNDays(interval) = self {
            try container.encode(Self.clampedDayInterval(interval), forKey: .dayInterval)
        }
    }

    var kind: Kind {
        switch self {
        case .runOnce: return .runOnce
        case .every15Minutes: return .every15Minutes
        case .hourly: return .hourly
        case .daily: return .daily
        case .everyNDays: return .everyNDays
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    var title: String {
        switch self {
        case .runOnce: return "仅运行一次"
        case .every15Minutes: return "每15分钟"
        case .hourly: return "每小时"
        case .daily: return "每天"
        case let .everyNDays(interval): return "每\(Self.clampedDayInterval(interval))天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }

    func nextRunDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .runOnce:
            return nil
        case .every15Minutes:
            return date.addingTimeInterval(15 * 60)
        case .hourly:
            return date.addingTimeInterval(60 * 60)
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case let .everyNDays(interval):
            return calendar.date(byAdding: .day, value: Self.clampedDayInterval(interval), to: date)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }

    static func from(kind: Kind, dayInterval: Int) -> AutomationFrequency {
        switch kind {
        case .runOnce:
            return .runOnce
        case .every15Minutes:
            return .every15Minutes
        case .hourly:
            return .hourly
        case .daily:
            return .daily
        case .everyNDays:
            return .everyNDays(clampedDayInterval(dayInterval))
        case .weekly:
            return .weekly
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        }
    }

    static func clampedDayInterval(_ value: Int) -> Int {
        min(max(value, 2), 7)
    }
}

struct AutomationFlow: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var prompt: String
    var frequency: AutomationFrequency
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastRunAt: Date?
    var nextRunAt: Date?

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名自动化" : trimmed
    }

    static func makeDefault(now: Date = Date()) -> AutomationFlow {
        AutomationFlow(
            id: UUID(),
            title: "新的自动化",
            prompt: "",
            frequency: .daily,
            isEnabled: true,
            createdAt: now,
            updatedAt: now,
            lastRunAt: nil,
            nextRunAt: now
        )
    }
}

enum AutomationStorageKeys {
    static let flows = "automationFlows"
}
