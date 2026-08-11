//
//  CommandPermissionModels.swift
//  看板娘
//
//  本地命令的审批策略与持久化配置。
//

import Foundation

enum CommandPermissionMode: String, CaseIterable, Identifiable {
    case alwaysAsk
    case askWhenRisky
    case allowAll
    case blacklist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysAsk: return "任何命令都询问"
        case .askWhenRisky: return "仅风险命令询问"
        case .allowAll: return "任何命令都允许"
        case .blacklist: return "黑名单模式"
        }
    }

    var detail: String {
        switch self {
        case .alwaysAsk:
            return "每次执行 Shell 命令前都需要你确认。"
        case .askWhenRisky:
            return "只读命令直接执行；写文件、联网、安装、进程和系统操作等需要确认。"
        case .allowAll:
            return "所有命令直接执行，不再显示确认。"
        case .blacklist:
            return "命中黑名单的命令会被拒绝，其余命令直接执行。"
        }
    }

    var systemImage: String {
        switch self {
        case .alwaysAsk: return "hand.raised.fill"
        case .askWhenRisky: return "checkmark.shield.fill"
        case .allowAll: return "exclamationmark.shield.fill"
        case .blacklist: return "nosign"
        }
    }
}

enum CommandPermissionStorage {
    static let modeKey = "commandPermissionMode"
    static let blacklistKey = "commandPermissionBlacklist"
    static let defaultMode = CommandPermissionMode.alwaysAsk
    static let defaultBlacklist = """
    sudo
    rm -rf /
    rm -rf ~
    diskutil erase
    mkfs
    shutdown
    reboot
    halt
    launchctl unload
    """
}

enum CommandPermissionDecision: Equatable {
    case allow
    case requireApproval
    case deny(matchedRule: String)
}

struct CommandPermissionPolicy {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func decision(for command: String) -> CommandPermissionDecision {
        let mode = CommandPermissionMode(
            rawValue: defaults.string(forKey: CommandPermissionStorage.modeKey) ?? ""
        ) ?? CommandPermissionStorage.defaultMode

        switch mode {
        case .alwaysAsk:
            return .requireApproval
        case .askWhenRisky:
            return Self.isRisky(command) ? .requireApproval : .allow
        case .allowAll:
            return .allow
        case .blacklist:
            if let rule = matchingBlacklistRule(for: command) {
                return .deny(matchedRule: rule)
            }
            return .allow
        }
    }

    private func matchingBlacklistRule(for command: String) -> String? {
        let configured = defaults.string(forKey: CommandPermissionStorage.blacklistKey)
            ?? CommandPermissionStorage.defaultBlacklist
        let normalizedCommand = Self.canonicalized(command)

        return configured
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first {
                !$0.isEmpty
                    && !$0.hasPrefix("#")
                    && normalizedCommand.contains(Self.canonicalized($0))
            }
    }

    private static func canonicalized(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// 风险模式刻意采用保守白名单：无法确定为只读的命令一律请求确认。
    private static func isRisky(_ command: String) -> Bool {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        let shellControlTokens = [";", "&&", "||", "|", ">", "<", "`", "$(", "${"]
        if shellControlTokens.contains(where: normalized.contains) {
            return true
        }

        let words = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = words.first else { return true }
        let commandName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        let arguments = Array(words.dropFirst()).map { $0.lowercased() }

        let readOnlyCommands: Set<String> = [
            "pwd", "ls", "cat", "head", "tail", "wc", "stat", "file", "du", "df",
            "grep", "egrep", "fgrep", "rg", "sort", "uniq", "diff", "cmp",
            "whoami", "id", "date", "uptime", "uname", "sw_vers", "arch", "hostname",
            "which", "whereis", "type", "printenv", "printf", "echo", "md5", "shasum"
        ]
        if readOnlyCommands.contains(commandName) {
            if commandName == "sort" {
                return arguments.contains { $0 == "-o" || $0.hasPrefix("--output") }
            }
            if commandName == "uniq" {
                return arguments.filter { !$0.hasPrefix("-") }.count > 1
            }
            return false
        }

        if commandName == "find" {
            let mutatingOptions = [
                "-delete", "-exec", "-execdir", "-ok", "-okdir",
                "-fls", "-fprint", "-fprint0", "-fprintf"
            ]
            return arguments.contains(where: mutatingOptions.contains)
        }

        if commandName == "git", let subcommand = arguments.first {
            if arguments.contains(where: { $0 == "--output" || $0.hasPrefix("--output=") }) {
                return true
            }
            let readOnlyGitSubcommands: Set<String> = [
                "status", "diff", "log", "show", "blame", "grep", "ls-files",
                "ls-tree", "rev-parse"
            ]
            if readOnlyGitSubcommands.contains(subcommand) {
                return false
            }
            if subcommand == "remote" {
                let mutatingRemoteActions: Set<String> = ["add", "remove", "rename", "set-head", "set-branches", "set-url", "prune", "update"]
                return arguments.dropFirst().contains(where: mutatingRemoteActions.contains)
            }
            if subcommand == "tag" {
                let mutatingTagOptions = ["-d", "--delete", "-f", "--force", "-a", "--annotate", "-s", "--sign"]
                return arguments.dropFirst().contains(where: mutatingTagOptions.contains)
                    || arguments.dropFirst().contains { !$0.hasPrefix("-") }
            }
            return true
        }

        return true
    }
}
