import Foundation
import Testing
@testable import SkillRouterCore

@Suite("Git 导入与确认更新")
struct GitImportAndUpdateTests {
    @Test
    func prefersAnIdenticalPackagedSkillOverARepositoryRootMirror() throws {
        try withGitFixture { fixture in
            let manifest = "---\nname: mirror\ndescription: 相同镜像\n---\n"
            try Data(manifest.utf8).write(to: fixture.repository.appendingPathComponent("SKILL.md"))
            try Data("网站文件".utf8).write(to: fixture.repository.appendingPathComponent("website.txt"))
            let packaged = fixture.repository.appendingPathComponent("plugins/mirror/skills/mirror", isDirectory: true)
            try FileManager.default.createDirectory(at: packaged, withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: packaged.appendingPathComponent("SKILL.md"))
            try Data("只属于打包 Skill".utf8).write(to: packaged.appendingPathComponent("payload.txt"))
            try fixture.commit("add mirrored package")

            let service = GitImportService(store: fixture.store, allowLocalRemotes: true)
            let prepared = try service.prepare(remoteURL: fixture.repository.path)
            let mirror = try SkillName(rawValue: "mirror")
            let candidate = try #require(prepared.candidates.first(where: { $0.name == mirror }))
            #expect(candidate.relativeDirectory == "plugins/mirror/skills/mirror")
            #expect(prepared.candidates.filter { $0.name == mirror }.count == 1)

            _ = try service.commit(
                prepared,
                selectedNames: [mirror],
                suiteName: try SuiteName(rawValue: "mirror-suite")
            )
            let imported = fixture.store.paths.suite(try SuiteName(rawValue: "mirror-suite"))
                .appendingPathComponent("mirror", isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: imported.appendingPathComponent("payload.txt").path))
            #expect(!FileManager.default.fileExists(atPath: imported.appendingPathComponent("website.txt").path))
        }
    }

    @Test
    func reportsBothPathsForGenuinelyDifferentDuplicateSkills() throws {
        try withGitFixture { fixture in
            try Data("---\nname: duplicate\ndescription: 根目录版本\n---\n".utf8)
                .write(to: fixture.repository.appendingPathComponent("SKILL.md"))
            let nested = fixture.repository.appendingPathComponent("packages/duplicate", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("---\nname: duplicate\ndescription: 另一个版本\n---\n".utf8)
                .write(to: nested.appendingPathComponent("SKILL.md"))
            try fixture.commit("add real duplicate")

            do {
                _ = try GitImportService(store: fixture.store, allowLocalRemotes: true)
                    .prepare(remoteURL: fixture.repository.path)
                Issue.record("应拒绝内容不同的同名 Skill")
            } catch {
                let message = error.localizedDescription
                #expect(message.contains("SKILL.md"))
                #expect(message.contains("packages/duplicate/SKILL.md"))
            }
        }
    }

    @Test
    func preparedImportCannotBeCommittedTwiceOrDeleteTheFirstSource() throws {
        try withGitFixture { fixture in
            let service = GitImportService(store: fixture.store, allowLocalRemotes: true)
            let prepared = try service.prepare(remoteURL: fixture.repository.path)
            let one = try SkillName(rawValue: "one")

            _ = try service.commit(
                prepared,
                selectedNames: [one],
                suiteName: try SuiteName(rawValue: "suite")
            )
            #expect(throws: SkillRouterError.self) {
                _ = try service.commit(
                    prepared,
                    selectedNames: [one],
                    suiteName: try SuiteName(rawValue: "suite")
                )
            }

            let sourceRepository = fixture.store.paths.sourcesDirectory
                .appendingPathComponent(prepared.sourceID.uuidString, isDirectory: true)
                .appendingPathComponent("repository", isDirectory: true)
            #expect(FileManager.default.fileExists(atPath: sourceRepository.path))
            #expect(try fixture.store.load().skill(named: one) != nil)
        }
    }

    @Test
    func checkDoesNotMutateCentralContentAndApplyDoes() throws {
        try withGitFixture { fixture in
            let suite = try SuiteName(rawValue: "superpowers")
            let one = try SkillName(rawValue: "one")
            let imported = try GitImportService(store: fixture.store, allowLocalRemotes: true).importSkills(
                from: fixture.repository.path,
                selectedNames: [one],
                suiteName: suite,
                now: Date(timeIntervalSince1970: 1)
            )
            #expect(imported.imported == [one])
            let centralManifest = fixture.store.paths.root
                .appendingPathComponent("Library/Suites/superpowers/one/SKILL.md")
            let original = try String(contentsOf: centralManifest, encoding: .utf8)

            try fixture.writeSkill(name: "one", description: "更新后")
            try fixture.commit("update one")
            let updater = GitUpdateService(store: fixture.store, allowLocalRemotes: true)
            let checks = try updater.checkForUpdates(force: true, now: Date(timeIntervalSince1970: 2))
            #expect(checks.single?.updateAvailable == true)
            #expect(try String(contentsOf: centralManifest, encoding: .utf8) == original)

            let sourceID = try #require(fixture.store.load().gitSources.single?.id)
            let applied = try updater.applyUpdate(sourceID: sourceID, now: Date(timeIntervalSince1970: 3))
            #expect(applied.updated == [one])
            #expect(try String(contentsOf: centralManifest, encoding: .utf8).contains("更新后"))
        }
    }

    @Test
    func upstreamRemovalCascadesProjectIntent() throws {
        try withGitFixture { fixture in
            let one = try SkillName(rawValue: "one")
            _ = try GitImportService(store: fixture.store, allowLocalRemotes: true)
                .importSkills(from: fixture.repository.path, selectedNames: [one], suiteName: try SuiteName(rawValue: "suite"))
            let project = fixture.root.appendingPathComponent("project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            let projects = ProjectService(store: fixture.store)
            _ = try projects.install(skillNames: [one], project: project, targetID: "codex", target: .codex)

            try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("one"))
            try fixture.commit("remove one")
            let sourceID = try #require(fixture.store.load().gitSources.single?.id)
            let applied = try GitUpdateService(store: fixture.store, allowLocalRemotes: true)
                .applyUpdate(sourceID: sourceID)

            #expect(applied.removed == [one])
            #expect(try fixture.store.load().skill(named: one) == nil)
            let manifest = try ProjectManifestStore().load(from: project)
            #expect(manifest.skills["one"] == nil)
            #expect(!FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills/one").path))
        }
    }

    @Test
    func automaticChecksAreThrottledForTwentyFourHours() throws {
        try withGitFixture { fixture in
            let one = try SkillName(rawValue: "one")
            _ = try GitImportService(store: fixture.store, allowLocalRemotes: true)
                .importSkills(from: fixture.repository.path, selectedNames: [one], suiteName: try SuiteName(rawValue: "suite"))
            let updater = GitUpdateService(store: fixture.store, allowLocalRemotes: true)
            let firstDate = Date(timeIntervalSince1970: 100)
            _ = try updater.checkForUpdates(force: false, now: firstDate)
            try FileManager.default.removeItem(at: fixture.repository)

            let throttled = try updater.checkForUpdates(force: false, now: firstDate.addingTimeInterval(60))
            #expect(throttled.count == 1)
            #expect(throws: SkillRouterError.self) {
                try updater.checkForUpdates(force: false, now: firstDate.addingTimeInterval(24 * 60 * 60 + 1))
            }
        }
    }

    @Test
    func projectCascadeFailureDoesNotRollbackAnAppliedCentralUpdate() throws {
        try withGitFixture { fixture in
            let one = try SkillName(rawValue: "one")
            _ = try GitImportService(store: fixture.store, allowLocalRemotes: true)
                .importSkills(from: fixture.repository.path, selectedNames: [one], suiteName: try SuiteName(rawValue: "suite"))
            let project = fixture.root.appendingPathComponent("project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            _ = try ProjectService(store: fixture.store).install(
                skillNames: [one], project: project, targetID: "codex", target: .codex
            )
            try FileManager.default.removeItem(at: project)
            try FileManager.default.removeItem(at: fixture.repository.appendingPathComponent("one"))
            try fixture.commit("remove one with missing project")
            let sourceID = try #require(fixture.store.load().gitSources.single?.id)

            let applied = try GitUpdateService(store: fixture.store, allowLocalRemotes: true)
                .applyUpdate(sourceID: sourceID)

            #expect(applied.removed == [one])
            #expect(applied.projectFailures.count == 1)
            #expect(try fixture.store.load().skill(named: one) == nil)
        }
    }

    private func withGitFixture(_ body: (GitFixture) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-tests-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = GitFixture(
            root: root,
            repository: repository,
            store: RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("central", isDirectory: true)))
        )
        try fixture.runGit(["init", "-q", "-b", "main"])
        try fixture.runGit(["config", "user.email", "tests@skill-router.local"])
        try fixture.runGit(["config", "user.name", "Skill Router Tests"])
        try fixture.writeSkill(name: "one", description: "初始一")
        try fixture.writeSkill(name: "two", description: "初始二")
        try fixture.commit("initial")
        try body(fixture)
    }
}

private struct GitFixture {
    let root: URL
    let repository: URL
    let store: RouterStateStore

    func writeSkill(name: String, description: String) throws {
        let directory = repository.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: \(description)\n---\n".utf8)
            .write(to: directory.appendingPathComponent("SKILL.md"))
    }

    func commit(_ message: String) throws {
        try runGit(["add", "-A"])
        try runGit(["commit", "-q", "-m", message])
    }

    func runGit(_ arguments: [String]) throws {
        let result = try ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            currentDirectory: repository
        )
        if result.exitCode != 0 {
            throw SkillRouterError.processFailed(
                executable: "/usr/bin/git",
                exitCode: result.exitCode,
                diagnostic: result.errorString
            )
        }
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
