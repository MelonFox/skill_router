import Foundation
import Testing
@testable import SkillRouterCore

@Suite(".skillrouter 导出与导入")
struct ArtifactServiceTests {
    @Test
    func exportsDeterministicallyAndRestoresCentralContentOnly() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("---\nname: example\n---\n".utf8).write(to: source.appendingPathComponent("SKILL.md"))
            let originalStore = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("original")))
            _ = try LocalImportService(store: originalStore).importSkills(from: source)
            let first = root.appendingPathComponent("first.skillrouter")
            let second = root.appendingPathComponent("second.skillrouter")
            let service = ArtifactService(store: originalStore)
            _ = try service.export(to: first)
            _ = try service.export(to: second)
            #expect(try Data(contentsOf: first) == Data(contentsOf: second))

            let restoredStore = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("restored")))
            let result = try ArtifactService(store: restoredStore).importArtifact(from: first)
            #expect(result.imported.map(\.rawValue) == ["example"])
            #expect(FileManager.default.fileExists(atPath: restoredStore.paths.root.appendingPathComponent("Library/Skills/example/SKILL.md").path))
            #expect((try restoredStore.load()).projects.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: restoredStore.paths.sourcesDirectory.appendingPathComponent("repository").path))
        }
    }

    @Test
    func rejectsFileCorruption() throws {
        try withTemporaryDirectory { root in
            let bundle = root.appendingPathComponent("bundle", isDirectory: true)
            let library = bundle.appendingPathComponent("Library/Skills/example", isDirectory: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            let content = Data("---\nname: example\n---\n".utf8)
            try content.write(to: library.appendingPathComponent("SKILL.md"))
            let name = try SkillName(rawValue: "example")
            let manifest = ArtifactManifest(
                skills: [ManagedSkillRecord(name: name, origin: .local, suiteName: nil, sourceID: nil, contentRelativePath: "Library/Skills/example", importedAt: Date())],
                suites: [],
                gitSources: [],
                files: [ArtifactFileRecord(path: "Library/Skills/example/SKILL.md", kind: .file, sha256: String(repeating: "0", count: 64), byteCount: Int64(content.count))]
            )
            try AtomicFileWriter().write(VersionedJSONCodec().encode(manifest), to: bundle.appendingPathComponent("manifest.json"))
            let archive = root.appendingPathComponent("corrupt.skillrouter")
            try ZipTool().createDeterministicArchive(contentsOf: bundle, at: archive)
            let store = RouterStateStore(paths: RouterPaths(root: root.appendingPathComponent("central")))
            #expect(throws: SkillRouterError.self) {
                try ArtifactService(store: store).importArtifact(from: archive)
            }
        }
    }

    @Test
    func rejectsTraversalAndDuplicateArchiveEntriesBeforeExtraction() {
        let zip = ZipTool()
        #expect(throws: SkillRouterError.self) {
            try zip.validateEntryPaths(["manifest.json", "../escape"])
        }
        #expect(throws: SkillRouterError.self) {
            try zip.validateEntryPaths(["manifest.json", "manifest.json"])
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
