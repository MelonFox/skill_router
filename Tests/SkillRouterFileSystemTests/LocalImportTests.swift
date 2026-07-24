import Foundation
import Testing
@testable import SkillRouterCore

@Suite("本地 Skill 导入")
struct LocalImportTests {
    @Test
    func discoversCandidatesAndExcludesDependencyDirectories() throws {
        try withTemporaryDirectory { root in
            try createSkill(named: "one", at: root.appendingPathComponent("skills/first"))
            try createSkill(named: "two", at: root.appendingPathComponent("skills/second"))
            try createSkill(named: "ignored", at: root.appendingPathComponent("node_modules/ignored"))
            try createSkill(named: "also-ignored", at: root.appendingPathComponent(".hidden/ignored"))

            let candidates = try SkillDiscovery().discover(in: root)
            #expect(candidates.map(\.name.rawValue) == ["one", "two"])
        }
    }

    @Test
    func importsSelectedSkillsAsALocalSuiteAndBuildsStableLinks() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source", isDirectory: true)
            let central = root.appendingPathComponent("central", isDirectory: true)
            try createSkill(named: "one", at: source.appendingPathComponent("one"))
            try createSkill(named: "two", at: source.appendingPathComponent("two"))
            try createSkill(named: "three", at: source.appendingPathComponent("three"))
            let outside = root.appendingPathComponent("outside.txt")
            try Data("outside".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(
                at: source.appendingPathComponent("one/outside-link"),
                withDestinationURL: outside
            )

            let store = RouterStateStore(paths: RouterPaths(root: central))
            let service = LocalImportService(store: store)
            let one = try SkillName(rawValue: "one")
            let three = try SkillName(rawValue: "three")
            let suite = try SuiteName(rawValue: "superpowers")
            let result = try service.importSkills(
                from: source,
                selectedNames: [one, three],
                suiteName: suite,
                now: Date(timeIntervalSince1970: 1)
            )

            #expect(result.imported == [one, three])
            let state = try store.load()
            #expect(state.skills.map(\.name) == [one, three])
            #expect(state.suites.single?.name == suite)

            let stableLink = store.paths.stableLink(one)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: stableLink.path) == "../Library/Suites/superpowers/one")
            #expect(FileManager.default.fileExists(atPath: stableLink.appendingPathComponent("SKILL.md").path))

            let preservedLink = central.appendingPathComponent("Library/Suites/superpowers/one/outside-link")
            #expect((try preservedLink.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: preservedLink.path) == outside.path)
        }
    }

    @Test(arguments: [
        CentralTransactionCheckpoint.afterJournalPrepared,
        .afterOldLibraryMoved,
        .afterNewLibraryInstalled,
        .afterStateSaved
    ])
    func recoversIdempotentlyAtEveryTransactionCheckpoint(
        checkpointToFail: CentralTransactionCheckpoint
    ) throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source", isDirectory: true)
            let central = root.appendingPathComponent("central", isDirectory: true)
            try createSkill(named: "one", at: source)
            let store = RouterStateStore(paths: RouterPaths(root: central))
            let service = LocalImportService(store: store, failureInjector: { checkpoint in
                if checkpoint == checkpointToFail {
                    throw SkillRouterError.io("测试注入中断")
                }
            })

            #expect(throws: SkillRouterError.self) {
                try service.importSkills(from: source)
            }
            try CentralTransactionManager(store: store).recoverPendingTransactions()
            try CentralTransactionManager(store: store).recoverPendingTransactions()

            let name = try SkillName(rawValue: "one")
            if checkpointToFail == .afterJournalPrepared {
                #expect(try store.load().skill(named: name) == nil)
                #expect(!FileManager.default.fileExists(atPath: store.paths.stableLink(name).path))
            } else {
                #expect(try store.load().skill(named: name) != nil)
                #expect(FileManager.default.fileExists(atPath: store.paths.stableLink(name).appendingPathComponent("SKILL.md").path))
            }
            let journals = try FileManager.default.contentsOfDirectory(atPath: store.paths.journalDirectory.path)
            #expect(journals.isEmpty)
        }
    }

    @Test
    func corruptTransactionJournalStopsFurtherCentralWrites() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source", isDirectory: true)
            let store = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("central")))
            try createSkill(named: "one", at: source)
            try store.initializeIfNeeded()
            try Data("损坏日志".utf8).write(to: store.paths.journalDirectory.appendingPathComponent("broken.json"))

            #expect(throws: SkillRouterError.self) {
                try LocalImportService(store: store).importSkills(from: source)
            }
            #expect(try store.load().skills.isEmpty)
        }
    }

    @Test
    func replacingTheLastGitSkillWithLocalContentRemovesItsSourceCache() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("local", isDirectory: true)
            let store = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("central")))
            try createSkill(named: "one", at: source)
            try store.initializeIfNeeded()
            let name = try SkillName(rawValue: "one")
            let sourceID = UUID()
            let existing = store.paths.standaloneSkill(name)
            try createSkill(named: "one", at: existing)
            let cache = store.paths.sourcesDirectory.appendingPathComponent(sourceID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try store.save(RouterState(
                skills: [ManagedSkillRecord(
                    name: name,
                    origin: .git,
                    suiteName: nil,
                    sourceID: sourceID,
                    contentRelativePath: "Library/Skills/one",
                    importedAt: Date()
                )],
                gitSources: [GitSourceRecord(
                    id: sourceID,
                    remoteURL: "https://example.com/repository.git",
                    suiteName: nil,
                    selectedSkills: [name],
                    lastAppliedCommit: "abc"
                )]
            ))

            _ = try LocalImportService(store: store).importSkills(
                from: source,
                conflictResolutions: [name: .replace]
            )

            let state = try store.load()
            #expect(state.skill(named: name)?.origin == .local)
            #expect(state.gitSources.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: cache.path))
        }
    }

    private func createSkill(named name: String, at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = "---\nname: \(name)\ndescription: 测试\n---\n"
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("SKILL.md"))
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
