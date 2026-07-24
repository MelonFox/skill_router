import Foundation
import Testing
@testable import SkillRouterCore

@Suite("文件系统基础能力")
struct StoragePrimitivesTests {
    @Test
    func createsOnlyTheInjectedRoot() throws {
        try withTemporaryDirectory { root in
            let paths = RouterPaths(root: root)
            try paths.createBaseDirectories()
            #expect(FileManager.default.fileExists(atPath: paths.standaloneSkillsDirectory.path))
            #expect(FileManager.default.fileExists(atPath: paths.suitesDirectory.path))
            #expect(FileManager.default.fileExists(atPath: paths.linksDirectory.path))
        }
    }

    @Test
    func atomicallyReplacesAFile() throws {
        try withTemporaryDirectory { root in
            let destination = root.appendingPathComponent("state.json")
            try Data("old".utf8).write(to: destination)
            try AtomicFileWriter().write(Data("new".utf8), to: destination)
            #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
        }
    }

    @Test
    func aSecondLockTimesOut() throws {
        try withTemporaryDirectory { root in
            let url = root.appendingPathComponent("state.lock")
            let first = try FileLock(url: url)
            let second = try FileLock(url: url)
            try first.lock()
            defer { first.unlock() }

            #expect(throws: SkillRouterError.stateBusy) {
                try second.lock(timeout: .milliseconds(40), pollInterval: .milliseconds(5))
            }
        }
    }

    @Test
    func rejectsArchiveTraversalPaths() {
        let zip = ZipTool()
        #expect(throws: SkillRouterError.self) {
            try zip.validateEntryPaths(["content/ok", "../escape"])
        }
        #expect(throws: Never.self) {
            try zip.validateEntryPaths(["bundle/manifest.json", "bundle/Skills/a/SKILL.md"])
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
