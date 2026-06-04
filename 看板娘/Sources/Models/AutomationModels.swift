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

    func nextRunDate(after date: Date, anchoredAt anchor: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .runOnce:
            return nil
        case .every15Minutes:
            return nextFixedIntervalDate(after: date, anchoredAt: anchor, interval: 15 * 60)
        case .hourly:
            return nextFixedIntervalDate(after: date, anchoredAt: anchor, interval: 60 * 60)
        case .daily:
            return nextCalendarDate(after: date, anchoredAt: anchor) {
                calendar.date(byAdding: .day, value: 1, to: $0)
            }
        case let .everyNDays(interval):
            return nextCalendarDate(after: date, anchoredAt: anchor) {
                calendar.date(byAdding: .day, value: Self.clampedDayInterval(interval), to: $0)
            }
        case .weekly:
            return nextCalendarDate(after: date, anchoredAt: anchor) {
                calendar.date(byAdding: .weekOfYear, value: 1, to: $0)
            }
        case .monthly:
            return nextCalendarDate(after: date, anchoredAt: anchor) {
                calendar.date(byAdding: .month, value: 1, to: $0)
            }
        case .yearly:
            return nextCalendarDate(after: date, anchoredAt: anchor) {
                calendar.date(byAdding: .year, value: 1, to: $0)
            }
        }
    }

    private func nextFixedIntervalDate(after date: Date, anchoredAt anchor: Date, interval: TimeInterval) -> Date {
        guard anchor <= date else { return anchor }

        let elapsed = date.timeIntervalSince(anchor)
        let completedIntervals = floor(elapsed / interval) + 1
        return anchor.addingTimeInterval(completedIntervals * interval)
    }

    private func nextCalendarDate(
        after date: Date,
        anchoredAt anchor: Date,
        advancingBy advance: (Date) -> Date?
    ) -> Date? {
        guard anchor <= date else { return anchor }

        var candidate = anchor
        for _ in 0..<10_000 {
            guard let next = advance(candidate) else { return nil }
            candidate = next
            if candidate > date {
                return candidate
            }
        }

        return nil
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
    var triggerId: UUID?
    var frequency: AutomationFrequency
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
    var scheduledAt: Date
    var lastRunAt: Date?
    var nextRunAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case prompt
        case triggerId
        case frequency
        case isEnabled
        case createdAt
        case updatedAt
        case scheduledAt
        case lastRunAt
        case nextRunAt
    }

    init(
        id: UUID,
        title: String,
        prompt: String,
        triggerId: UUID?,
        frequency: AutomationFrequency,
        isEnabled: Bool,
        createdAt: Date,
        updatedAt: Date,
        scheduledAt: Date,
        lastRunAt: Date?,
        nextRunAt: Date?
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.triggerId = triggerId
        self.frequency = frequency
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledAt = scheduledAt
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        triggerId = try container.decodeIfPresent(UUID.self, forKey: .triggerId)
        frequency = try container.decode(AutomationFrequency.self, forKey: .frequency)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        nextRunAt = try container.decodeIfPresent(Date.self, forKey: .nextRunAt)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? nextRunAt ?? createdAt
    }

    var normalizedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名自动化" : trimmed
    }

    static func makeDefault(now: Date = Date()) -> AutomationFlow {
        AutomationFlow(
            id: UUID(),
            title: "新的自动化",
            prompt: "",
            triggerId: nil,
            frequency: .daily,
            isEnabled: true,
            createdAt: now,
            updatedAt: now,
            scheduledAt: now,
            lastRunAt: nil,
            nextRunAt: now
        )
    }
}

enum AutomationStorageKeys {
    static let flows = "automationFlows"
}
