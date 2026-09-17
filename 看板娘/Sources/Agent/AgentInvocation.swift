//
//  AgentInvocation.swift
//  看板娘
//
//  Explicit tool and Skill invocations entered from the chat composer.
//

import Foundation

enum AgentInvocationKind: String, Codable, CaseIterable {
    case tool
    case skill

    var prefix: Character {
        switch self {
        case .tool: "/"
        case .skill: "$"
        }
    }

    var title: String {
        switch self {
        case .tool: "工具"
        case .skill: "技能"
        }
    }
}

struct AgentInvocation: Codable, Equatable {
    let kind: AgentInvocationKind
    let name: String
}

struct AgentInvocationOption: Identifiable, Equatable {
    let kind: AgentInvocationKind
    let name: String
    let description: String

    var id: String { "\(kind.rawValue):\(name.lowercased())" }
    var token: String { "\(kind.prefix)\(name)" }
}

struct AgentInvocationQuery: Equatable {
    let kind: AgentInvocationKind
    let term: String
}

struct AgentInvocationSubmission: Equatable {
    let visibleText: String
    let instruction: String
    let invocation: AgentInvocation?
}

enum AgentInvocationParser {
    /// Suggestions are intentionally limited to the first, still-uncommitted
    /// token. Once whitespace follows the token the picker closes.
    static func query(in text: String) -> AgentInvocationQuery? {
        guard let first = text.first,
              let kind = kind(for: first) else { return nil }

        let term = String(text.dropFirst())
        guard term.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return AgentInvocationQuery(kind: kind, term: term)
    }

    static func filteredOptions(
        for query: AgentInvocationQuery,
        in options: [AgentInvocationOption]
    ) -> [AgentInvocationOption] {
        options.filter { option in
            guard option.kind == query.kind else { return false }
            guard !query.term.isEmpty else { return true }
            return option.name.localizedCaseInsensitiveContains(query.term)
                || option.description.localizedCaseInsensitiveContains(query.term)
        }
    }

    static func replacingQuery(in text: String, with option: AgentInvocationOption) -> String {
        guard query(in: text)?.kind == option.kind else { return text }
        return option.token + " "
    }

    static func submission(
        from rawText: String,
        options: [AgentInvocationOption]
    ) -> AgentInvocationSubmission {
        let visibleText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = visibleText.first,
              let kind = kind(for: first) else {
            return AgentInvocationSubmission(
                visibleText: visibleText,
                instruction: visibleText,
                invocation: nil
            )
        }

        let tokenEnd = visibleText.firstIndex(where: { $0.isWhitespace }) ?? visibleText.endIndex
        let requestedName = String(visibleText[visibleText.index(after: visibleText.startIndex)..<tokenEnd])
        guard let option = options.first(where: {
            $0.kind == kind && $0.name.caseInsensitiveCompare(requestedName) == .orderedSame
        }) else {
            return AgentInvocationSubmission(
                visibleText: visibleText,
                instruction: visibleText,
                invocation: nil
            )
        }

        let remainder = String(visibleText[tokenEnd...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackInstruction: String
        switch kind {
        case .tool:
            fallbackInstruction = "我已显式附加此工具，请把它作为本轮可用上下文，并根据实际任务决定是否使用。"
        case .skill:
            fallbackInstruction = "我已显式附加此技能，请把它作为本轮可用上下文，并根据实际任务决定如何使用。"
        }
        return AgentInvocationSubmission(
            visibleText: visibleText,
            instruction: remainder.isEmpty ? fallbackInstruction : remainder,
            invocation: AgentInvocation(kind: kind, name: option.name)
        )
    }

    private static func kind(for prefix: Character) -> AgentInvocationKind? {
        AgentInvocationKind.allCases.first(where: { $0.prefix == prefix })
    }
}

@MainActor
enum AgentInvocationCatalog {
    static func options(
        defaults: UserDefaults = .standard,
        registry: AgentToolRegistry = .standard()
    ) -> [AgentInvocationOption] {
        let tools = registry.definitions
            .filter { $0.name != "read_skill" }
            .map {
                AgentInvocationOption(
                    kind: .tool,
                    name: $0.name,
                    description: $0.description
                )
            }

        let skills = SkillLibrary.load(defaults: defaults)
            .filter { $0.isEnabled && $0.isValid }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                AgentInvocationOption(
                    kind: .skill,
                    name: $0.name,
                    description: $0.description
                )
            }

        return tools + skills
    }
}
