import Foundation
import Testing
@testable import SkillRouterCore

@Suite("Git 与 ZIP 系统适配")
struct GitAndZipTests {
    @Test
    func readsHeadFromALocalRepository() throws {
        try withTemporaryDirectory { root in
            let repository = root.appendingPathComponent("repo", isDirectory: true)
            try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
            let runner = ProcessRunner()
            for arguments in [
                ["init", "-q"],
                ["config", "user.email", "tests@skill-router.local"],
                ["config", "user.name", "Skill Router Tests"]
            ] {
                let result = try runner.run(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: arguments, currentDirectory: repository)
                #expect(result.exitCode == 0)
            }
            try Data("hello".utf8).write(to: repository.appendingPathComponent("README.md"))
            for arguments in [["add", "README.md"], ["commit", "-q", "-m", "initial"]] {
                let result = try runner.run(executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: arguments, currentDirectory: repository)
                #expect(result.exitCode == 0)
            }

            let head = try GitClient().headCommit(in: repository)
            #expect(head.count == 40)
        }
    }

    @Test
    func createsListsAndExtractsZip() throws {
        try withTemporaryDirectory { root in
            let content = root.appendingPathComponent("bundle", isDirectory: true)
            try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: content.appendingPathComponent("manifest.json"))
            let archive = root.appendingPathComponent("test.skillrouter")
            let extracted = root.appendingPathComponent("extracted", isDirectory: true)

            let zip = ZipTool()
            try zip.createArchive(from: content, at: archive)
            let entries = try zip.listEntries(in: archive)
            #expect(entries.contains("bundle/manifest.json"))
            try zip.extractArchive(archive, to: extracted)
            #expect(FileManager.default.fileExists(atPath: extracted.appendingPathComponent("bundle/manifest.json").path))
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
