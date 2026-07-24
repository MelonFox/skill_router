import Foundation
import Testing
@testable import SkillRouterCore

@Suite("中央 Skill 删除")
struct CentralLibraryServiceTests {
    @Test
    func deletesCentralContentAndCascadesProject() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("---\nname: example\n---\n".utf8).write(to: source.appendingPathComponent("SKILL.md"))
        let store = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("central")))
        _ = try LocalImportService(store: store).importSkills(from: source)
        let name = try SkillName(rawValue: "example")
        _ = try ProjectService(store: store).install(
            skillNames: [name],
            project: project,
            targetID: "codex",
            target: .codex
        )

        let result = try CentralLibraryService(store: store).delete(skillNames: [name])
        #expect(result.deleted == [name])
        #expect(try store.load().skills.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.paths.root.appendingPathComponent("Library/Skills/example").path))
        #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills/example").path))
        #expect(try ProjectManifestStore().load(from: project).skills.isEmpty)
    }

    @Test
    func renamesAnEntireSuiteAndKeepsStableLinksValid() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        for name in ["one", "two"] {
            let skill = source.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            try Data("---\nname: \(name)\n---\n".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        }
        let store = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("central")))
        let oldName = try SuiteName(rawValue: "old-suite")
        let newName = try SuiteName(rawValue: "new-suite")
        _ = try LocalImportService(store: store).importSkills(from: source, suiteName: oldName)

        let result = try CentralLibraryService(store: store).renameSuite(from: oldName, to: newName)

        #expect(result.skills.map(\.rawValue) == ["one", "two"])
        let state = try store.load()
        #expect(state.suites.count == 1)
        #expect(state.suites.first?.name == newName)
        #expect(state.skills.allSatisfy { $0.suiteName == newName })
        #expect(!FileManager.default.fileExists(atPath: store.paths.suite(oldName).path))
        #expect(FileManager.default.fileExists(atPath: store.paths.suite(newName).appendingPathComponent("one/SKILL.md").path))
        let stableDestination = try FileManager.default.destinationOfSymbolicLink(
            atPath: store.paths.stableLink(try SkillName(rawValue: "one")).path
        )
        #expect(stableDestination == "../Library/Suites/new-suite/one")
    }
}
