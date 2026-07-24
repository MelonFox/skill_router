import Foundation
import Testing
@testable import SkillRouterCore

@Suite("系统 Skill 安装")
struct SystemSkillInstallerTests {
    @Test
    func installsCLIResourceAndBothGlobalEntries() throws {
        try withTemporaryDirectory { root in
            let central = root.appendingPathComponent("central", isDirectory: true)
            let home = root.appendingPathComponent("home", isDirectory: true)
            let sourceCLI = root.appendingPathComponent("skill-router-source")
            try Data("binary".utf8).write(to: sourceCLI)

            let installer = SystemSkillInstaller(paths: RouterPaths(root: central), homeDirectory: home)
            let result = try installer.install(cliSource: sourceCLI)
            #expect(!result.hasConflicts)
            #expect(FileManager.default.isExecutableFile(atPath: result.cliPath))

            let manifest = central.appendingPathComponent("system-skills/skill-router/SKILL.md")
            let parsed = try SkillManifestParser().parse(fileAt: manifest)
            #expect(parsed.name.rawValue == "skill-router")

            for path in [
                home.appendingPathComponent(".agents/skills/skill-router"),
                home.appendingPathComponent(".claude/skills/skill-router")
            ] {
                #expect((try path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true)
                #expect(FileManager.default.fileExists(atPath: path.appendingPathComponent("SKILL.md").path))
            }
        }
    }

    @Test
    func neverOverwritesAnUnmanagedGlobalEntry() throws {
        try withTemporaryDirectory { root in
            let central = root.appendingPathComponent("central", isDirectory: true)
            let home = root.appendingPathComponent("home", isDirectory: true)
            let sourceCLI = root.appendingPathComponent("skill-router-source")
            try Data("binary".utf8).write(to: sourceCLI)
            let conflict = home.appendingPathComponent(".agents/skills/skill-router", isDirectory: true)
            try FileManager.default.createDirectory(at: conflict, withIntermediateDirectories: true)
            try Data("用户内容".utf8).write(to: conflict.appendingPathComponent("KEEP"))

            let result = try SystemSkillInstaller(paths: RouterPaths(root: central), homeDirectory: home)
                .install(cliSource: sourceCLI)
            #expect(result.hasConflicts)
            #expect(try String(contentsOf: conflict.appendingPathComponent("KEEP"), encoding: .utf8) == "用户内容")
        }
    }

    @Test
    func bootstrapRespectsPersistedDisabledEntries() throws {
        try withTemporaryDirectory { root in
            let central = root.appendingPathComponent("central", isDirectory: true)
            let home = root.appendingPathComponent("home", isDirectory: true)
            let sourceCLI = root.appendingPathComponent("skill-router-source")
            try Data("binary".utf8).write(to: sourceCLI)
            let store = RouterStateStore(paths: RouterPaths(root: central))
            try store.save(RouterState(systemSkill: SystemSkillSettings(
                codexEnabled: false,
                claudeCodeEnabled: true
            )))

            let result = try BootstrapService().bootstrap(
                environment: [
                    "SKILL_ROUTER_HOME": central.path,
                    "SKILL_ROUTER_CLI_SOURCE": sourceCLI.path
                ],
                homeDirectory: home,
                appExecutable: nil
            )

            #expect(result.entries.first(where: { $0.agent == "codex" })?.status == .disabled)
            #expect(result.entries.first(where: { $0.agent == "claude-code" })?.status == .installed)
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/skill-router").path))
            #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/skills/skill-router/SKILL.md").path))
        }
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}
