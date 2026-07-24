import Foundation
import Testing
@testable import SkillRouterCore

@Suite("项目清单与软链接分发")
struct ProjectDistributionTests {
    @Test
    func installsAnAbsoluteTwoLayerSymlink() throws {
        try withFixture { fixture in
            let result = try fixture.projects.install(
                skillNames: [fixture.skillName],
                project: fixture.project,
                targetID: "codex",
                target: .codex
            )
            #expect(!result.isPartial)

            let projectLink = fixture.project.appendingPathComponent(".agents/skills/example")
            let projectDestination = try FileManager.default.destinationOfSymbolicLink(atPath: projectLink.path)
            #expect(projectDestination == fixture.store.paths.stableLink(fixture.skillName).path)
            #expect(projectDestination.hasPrefix("/"))

            let stableDestination = try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.store.paths.stableLink(fixture.skillName).path
            )
            #expect(stableDestination == "../Library/Skills/example")
            #expect(FileManager.default.fileExists(atPath: projectLink.appendingPathComponent("SKILL.md").path))
        }
    }

    @Test
    func preservesUnmanagedConflictAndKeepsIntent() throws {
        try withFixture { fixture in
            let target = fixture.project.appendingPathComponent(".agents/skills", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let conflict = target.appendingPathComponent("example")
            try Data("用户文件".utf8).write(to: conflict)

            let result = try fixture.projects.install(
                skillNames: [fixture.skillName],
                project: fixture.project,
                targetID: "codex",
                target: .codex
            )
            #expect(result.isPartial)
            #expect(result.reconciliation.items.contains { $0.status == .conflict })
            #expect(try String(contentsOf: conflict, encoding: .utf8) == "用户文件")
            let manifest = try ProjectManifestStore().load(from: fixture.project)
            #expect(manifest.skills["example"]?.targets == ["codex"])
        }
    }

    @Test
    func skipsMissingNamesButInstallsValidSubset() throws {
        try withFixture { fixture in
            let missing = try SkillName(rawValue: "missing")
            let result = try fixture.projects.install(
                skillNames: [fixture.skillName, missing],
                project: fixture.project,
                targetID: "claude-code",
                target: .claudeCode
            )
            #expect(result.isPartial)
            #expect(result.missing == ["missing"])
            let manifest = try ProjectManifestStore().load(from: fixture.project)
            #expect(manifest.skills["example"] != nil)
            #expect(manifest.skills["missing"] == nil)
        }
    }

    @Test
    func uninstallAllRetainsTargetsAndRegistration() throws {
        try withFixture { fixture in
            _ = try fixture.projects.install(
                skillNames: [fixture.skillName],
                project: fixture.project,
                targetID: "codex",
                target: .codex
            )
            _ = try fixture.projects.uninstallAll(project: fixture.project)
            let manifest = try ProjectManifestStore().load(from: fixture.project)
            #expect(manifest.skills.isEmpty)
            #expect(manifest.targets["codex"] == .codex)
            #expect(try fixture.projects.registeredProjects().contains { $0.path == fixture.project.path })
            #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/example").path))
        }
    }

    @Test
    func unregisterDoesNotTouchManifestOrLinks() throws {
        try withFixture { fixture in
            _ = try fixture.projects.install(
                skillNames: [fixture.skillName],
                project: fixture.project,
                targetID: "codex",
                target: .codex
            )
            try fixture.projects.unregister(project: fixture.project)
            #expect(try fixture.projects.registeredProjects().isEmpty)
            #expect(FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".skill-router.json").path))
            #expect((try fixture.project.appendingPathComponent(".agents/skills/example").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true)
        }
    }

    @Test
    func uninstallsOneSkillAndAddsExactGitIgnoreEntryIdempotently() throws {
        try withFixture { fixture in
            _ = try fixture.projects.install(
                skillNames: [fixture.skillName],
                project: fixture.project,
                targetID: "codex",
                target: .codex
            )
            #expect(try fixture.projects.gitIgnoreEntries(project: fixture.project) == ["/.agents/skills/example"])
            #expect(try fixture.projects.addGitIgnoreEntries(project: fixture.project) == ["/.agents/skills/example"])
            #expect(try fixture.projects.addGitIgnoreEntries(project: fixture.project).isEmpty)
            let gitIgnore = try String(contentsOf: fixture.project.appendingPathComponent(".gitignore"), encoding: .utf8)
            #expect(gitIgnore.components(separatedBy: "/.agents/skills/example").count == 2)

            _ = try fixture.projects.uninstall(skillNames: [fixture.skillName], project: fixture.project)
            #expect(try ProjectManifestStore().load(from: fixture.project).skills.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: fixture.project.appendingPathComponent(".agents/skills/example").path))
        }
    }

    @Test
    func resolvesARegisteredProjectAfterItMoves() throws {
        try withFixture { fixture in
            _ = try fixture.projects.register(project: fixture.project)
            let moved = fixture.project.deletingLastPathComponent()
                .appendingPathComponent("project-moved", isDirectory: true)
            try FileManager.default.moveItem(at: fixture.project, to: moved)

            let projects = try fixture.projects.registeredProjects()
            #expect(projects.count == 1)
            #expect(projects.first?.path == moved.path)
            let stored = try fixture.store.load().projects
            #expect(stored.count == 1)
            #expect(stored.first?.path == moved.path)
        }
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let central = root.appendingPathComponent("central", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("---\nname: example\n---\n".utf8).write(to: source.appendingPathComponent("SKILL.md"))

        let store = RouterStateStore(paths: RouterPaths(root: central))
        _ = try LocalImportService(store: store).importSkills(from: source)
        let skillName = try SkillName(rawValue: "example")
        let projects = ProjectService(store: store)
        try body(Fixture(store: store, projects: projects, project: project, skillName: skillName))
    }
}

private struct Fixture {
    let store: RouterStateStore
    let projects: ProjectService
    let project: URL
    let skillName: SkillName
}
