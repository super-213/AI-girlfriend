//
//  PreferencesModels.swift
//  桌面宠物应用
//
//  偏好设置相关的数据模型
//

import Foundation

// MARK: - Agent/Skill 文件存储键

enum AgentSkillStorageKeys {
    static let agentFile = "agentFile"
    static let skillFiles = "skillFiles"
    static let agentTemplateVersion = "agentTemplateVersion"
}

// MARK: - Agent/Skill 文件模型

/// 单个 agent.md 文件记录
struct AgentFile: Codable, Equatable {
    var name: String
    var path: String
    var updatedAt: Date
}

/// skill.md 文件记录（可多个）
struct SkillFile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var fileName: String
    var path: String
    var isEnabled: Bool
    var validationError: String?
    var addedAt: Date
    var updatedAt: Date

    var isValid: Bool { validationError == nil }

    init(
        id: UUID,
        name: String,
        description: String,
        fileName: String,
        path: String,
        isEnabled: Bool = true,
        validationError: String? = nil,
        addedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.fileName = fileName
        self.path = path
        self.isEnabled = isEnabled
        self.validationError = validationError
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, fileName, path, isEnabled, validationError, addedAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        path = try values.decode(String.self, forKey: .path)
        let legacyName = try values.decode(String.self, forKey: .name)
        name = legacyName
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
            ?? URL(fileURLWithPath: path).lastPathComponent
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        validationError = try values.decodeIfPresent(String.self, forKey: .validationError)
        addedAt = try values.decode(Date.self, forKey: .addedAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? addedAt
    }
}

struct SkillManifest: Equatable {
    let name: String
    let description: String
}

enum SkillManifestError: LocalizedError, Equatable {
    case missingFrontMatter
    case unclosedFrontMatter
    case missingName
    case invalidName
    case missingDescription
    case invalidDescription

    var errorDescription: String? {
        switch self {
        case .missingFrontMatter:
            return "SKILL.md 必须以 --- YAML front matter 开头"
        case .unclosedFrontMatter:
            return "SKILL.md 的 YAML front matter 缺少结束 ---"
        case .missingName:
            return "front matter 缺少 name"
        case .invalidName:
            return "name 必须为 1-64 个字符，且不能包含空格或路径分隔符"
        case .missingDescription:
            return "front matter 缺少 description"
        case .invalidDescription:
            return "description 不能超过 1024 个字符"
        }
    }
}

enum SkillManifestParser {
    static func parse(_ source: String) throws -> SkillManifest {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.first?.hasPrefix("\u{feff}") == true {
            lines[0].removeFirst()
        }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SkillManifestError.missingFrontMatter
        }
        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            throw SkillManifestError.unclosedFrontMatter
        }

        let frontMatter = Array(lines[1..<closingIndex])
        let values = parseTopLevelValues(frontMatter)
        let name = unquote(values["name"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let description = unquote(values["description"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { throw SkillManifestError.missingName }
        guard name.count <= 64,
              name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !name.contains("/"), !name.contains("\\") else {
            throw SkillManifestError.invalidName
        }
        guard !description.isEmpty else { throw SkillManifestError.missingDescription }
        guard description.count <= 1_024 else { throw SkillManifestError.invalidDescription }
        return SkillManifest(name: name, description: description)
    }

    private static func parseTopLevelValues(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard !line.isEmpty, !line.first!.isWhitespace,
                  let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }

            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if value == ">" || value == "|" {
                let preservesNewlines = value == "|"
                var continuation: [String] = []
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    guard next.isEmpty || next.first?.isWhitespace == true else { break }
                    continuation.append(next.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                value = continuation.joined(separator: preservesNewlines ? "\n" : " ")
                result[key] = value
                continue
            }
            result[key] = value
            index += 1
        }
        return result
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

enum SkillLibrary {
    static func load(defaults: UserDefaults = .standard) -> [SkillFile] {
        guard let data = defaults.data(forKey: AgentSkillStorageKeys.skillFiles),
              let saved = try? JSONDecoder().decode([SkillFile].self, from: data) else {
            return []
        }
        return refresh(saved)
    }

    static func makeRecord(
        id: UUID = UUID(),
        fileURL: URL,
        content: String,
        isEnabled: Bool = true,
        addedAt: Date = .now,
        updatedAt: Date = .now
    ) -> SkillFile {
        do {
            let manifest = try SkillManifestParser.parse(content)
            return SkillFile(
                id: id,
                name: manifest.name,
                description: manifest.description,
                fileName: fileURL.lastPathComponent,
                path: fileURL.path,
                isEnabled: isEnabled,
                addedAt: addedAt,
                updatedAt: updatedAt
            )
        } catch {
            return SkillFile(
                id: id,
                name: fileURL.deletingPathExtension().lastPathComponent,
                description: "",
                fileName: fileURL.lastPathComponent,
                path: fileURL.path,
                isEnabled: false,
                validationError: error.localizedDescription,
                addedAt: addedAt,
                updatedAt: updatedAt
            )
        }
    }

    static func refresh(_ skills: [SkillFile], fileManager: FileManager = .default) -> [SkillFile] {
        var refreshed: [SkillFile] = []
        for skill in skills where fileManager.fileExists(atPath: skill.path) {
            let url = URL(fileURLWithPath: skill.path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                var unreadable = skill
                unreadable.isEnabled = false
                unreadable.validationError = "无法读取 SKILL.md"
                refreshed.append(unreadable)
                continue
            }
            let attributes = try? fileManager.attributesOfItem(atPath: skill.path)
            let modifiedAt = attributes?[.modificationDate] as? Date ?? skill.updatedAt
            var current = makeRecord(
                id: skill.id,
                fileURL: url,
                content: content,
                isEnabled: skill.isEnabled,
                addedAt: skill.addedAt,
                updatedAt: modifiedAt
            )
            if current.validationError != nil { current.isEnabled = false }
            refreshed.append(current)
        }

        let groups = Dictionary(grouping: refreshed.indices, by: { refreshed[$0].name.lowercased() })
        for indices in groups.values where indices.count > 1 {
            for index in indices {
                refreshed[index].isEnabled = false
                refreshed[index].validationError = "技能名称重复：\(refreshed[index].name)"
            }
        }
        return refreshed
    }

    static func enabledCatalog(defaults: UserDefaults = .standard) -> [[String: String]] {
        load(defaults: defaults)
            .filter { $0.isEnabled && $0.isValid }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { ["name": $0.name, "description": $0.description] }
    }

    static func enabledSkill(named name: String, defaults: UserDefaults = .standard) -> SkillFile? {
        load(defaults: defaults).first {
            $0.isEnabled && $0.isValid && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }
}
