import Foundation
import SkillRouterCLIKit
import SkillRouterCore
import Testing

@Suite("CLI 契约")
struct CLITests {
    @Test
    func helpAndVersionUseStdout() {
        let cli = SkillRouterCLI()
        let help = cli.run(arguments: ["help"], environment: [:], currentDirectory: URL(fileURLWithPath: "/"))
        #expect(help.exitCode == 0)
        #expect(help.standardOutput.contains("项目侧命令行工具"))
        #expect(help.standardError.isEmpty)

        let version = cli.run(arguments: ["--version"], environment: [:], currentDirectory: URL(fileURLWithPath: "/"))
        #expect(version.standardOutput.contains(SkillRouterCLI.version))
    }

    @Test
    func usageErrorsUseStderrAndExit64() {
        let execution = SkillRouterCLI().run(
            arguments: ["project", "install"],
            environment: [:],
            currentDirectory: URL(fileURLWithPath: "/")
        )
        #expect(execution.exitCode == CLIExitCode.usage.rawValue)
        #expect(execution.standardOutput.isEmpty)
        #expect(execution.standardError.contains("至少需要一个 Skill"))
    }

    @Test
    func jsonErrorsAreVersionedAndStayOnStderr() throws {
        let execution = SkillRouterCLI().run(
            arguments: ["project", "unknown", "--json"],
            environment: [:],
            currentDirectory: URL(fileURLWithPath: "/")
        )
        #expect(execution.exitCode == CLIExitCode.usage.rawValue)
        #expect(execution.standardOutput.isEmpty)
        let object = try #require(JSONSerialization.jsonObject(with: Data(execution.standardError.utf8)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["success"] as? Bool == false)
        #expect(object["exitCode"] as? Int == 64)
    }

    @Test
    func projectListUsesInjectedHome() throws {
        try withTemporaryDirectory { root in
            let project = root.appendingPathComponent("project", isDirectory: true)
            let central = root.appendingPathComponent("central", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let cli = SkillRouterCLI()
            let environment = ["SKILL_ROUTER_HOME": central.path]

            let registered = cli.run(
                arguments: ["project", "register", "--path", project.path, "--target", "codex"],
                environment: environment,
                currentDirectory: project
            )
            #expect(registered.exitCode == 0)

            let list = cli.run(
                arguments: ["project", "list", "--json"],
                environment: environment,
                currentDirectory: project
            )
            #expect(list.exitCode == 0)
            #expect(list.standardError.isEmpty)
            #expect(list.standardOutput.contains(project.path))
            #expect(!FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".skill-router/state.json").path) || central.path != FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".skill-router").path)
        }
    }

    @Test
    func customTargetUsesTheRegisteredManifestPathInsteadOfFallingBackToCodex() throws {
        try withTemporaryDirectory { root in
            let project = root.appendingPathComponent("project", isDirectory: true)
            let source = root.appendingPathComponent("source", isDirectory: true)
            let central = root.appendingPathComponent("central", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("---\nname: example\n---\n".utf8).write(to: source.appendingPathComponent("SKILL.md"))
            let store = RouterStateStore(paths: RouterPaths(root: central))
            _ = try LocalImportService(store: store).importSkills(from: source)
            let custom = try DistributionTargetRecord(type: .custom, path: "tools/skills")
            _ = try ProjectService(store: store).register(project: project, targetID: "tools", target: custom)

            let execution = SkillRouterCLI().run(
                arguments: ["project", "install", "example", "--path", project.path, "--target", "tools"],
                environment: ["SKILL_ROUTER_HOME": central.path],
                currentDirectory: project
            )

            #expect(execution.exitCode == 0)
            #expect(FileManager.default.fileExists(atPath: project.appendingPathComponent("tools/skills/example/SKILL.md").path))
            #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills/example").path))

            let unknown = SkillRouterCLI().run(
                arguments: ["project", "install", "example", "--path", project.path, "--target", "unknown"],
                environment: ["SKILL_ROUTER_HOME": central.path],
                currentDirectory: project
            )
            #expect(unknown.exitCode == CLIExitCode.ioFailure.rawValue)
            #expect(unknown.standardError.contains("尚未登记自定义目标"))
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
