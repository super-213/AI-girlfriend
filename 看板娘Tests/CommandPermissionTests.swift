import Foundation
import Testing
@testable import 看板娘

struct CommandPermissionPolicyTests {
    @Test
    func defaultModeAsksBeforeEveryCommand() {
        withDefaults { defaults in
            let policy = CommandPermissionPolicy(defaults: defaults)

            #expect(policy.decision(for: "pwd") == .requireApproval)
            #expect(policy.decision(for: "rm notes.txt") == .requireApproval)
        }
    }

    @Test
    func riskModeAllowsReadOnlyCommandsAndAsksForMutations() {
        withDefaults { defaults in
            defaults.set(CommandPermissionMode.askWhenRisky.rawValue, forKey: CommandPermissionStorage.modeKey)
            let policy = CommandPermissionPolicy(defaults: defaults)

            #expect(policy.decision(for: "ls -la") == .allow)
            #expect(policy.decision(for: "git status") == .allow)
            #expect(policy.decision(for: "rm notes.txt") == .requireApproval)
            #expect(policy.decision(for: "git push") == .requireApproval)
            #expect(policy.decision(for: "cat notes.txt | sort") == .requireApproval)
            #expect(policy.decision(for: "sort notes.txt -o sorted.txt") == .requireApproval)
            #expect(policy.decision(for: "find . -exec touch {} ;") == .requireApproval)
            #expect(policy.decision(for: "git diff --output=changes.patch") == .requireApproval)
        }
    }

    @Test
    func allowAllModeDoesNotAskEvenForDestructiveCommands() {
        withDefaults { defaults in
            defaults.set(CommandPermissionMode.allowAll.rawValue, forKey: CommandPermissionStorage.modeKey)
            let policy = CommandPermissionPolicy(defaults: defaults)

            #expect(policy.decision(for: "rm -rf ./build") == .allow)
            #expect(policy.decision(for: "sudo launchctl kickstart system/example") == .allow)
        }
    }

    @Test
    func blacklistModeDeniesMatchingRulesAndAllowsEverythingElse() {
        withDefaults { defaults in
            defaults.set(CommandPermissionMode.blacklist.rawValue, forKey: CommandPermissionStorage.modeKey)
            defaults.set("# comment\nsudo\nrm -rf /", forKey: CommandPermissionStorage.blacklistKey)
            let policy = CommandPermissionPolicy(defaults: defaults)

            #expect(policy.decision(for: "echo ok") == .allow)
            #expect(policy.decision(for: "SUDO -n true") == .deny(matchedRule: "sudo"))
            #expect(policy.decision(for: "rm   -rf   /tmp/cache") == .deny(matchedRule: "rm -rf /"))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "CommandPermissionPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
