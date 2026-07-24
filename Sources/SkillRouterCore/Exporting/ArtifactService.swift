import CryptoKit
import Foundation

public struct ArtifactExportResult: Equatable, Sendable {
    public let destination: URL
    public let skillNames: [SkillName]
    public let fileCount: Int
}

public struct ArtifactImportOptions: Sendable {
    public var skillConflicts: [SkillName: SkillConflictResolution]
    public var suiteRenames: [SuiteName: SuiteName]
    public var skippedSuites: Set<SuiteName>

    public init(
        skillConflicts: [SkillName: SkillConflictResolution] = [:],
        suiteRenames: [SuiteName: SuiteName] = [:],
        skippedSuites: Set<SuiteName> = []
    ) {
        self.skillConflicts = skillConflicts
        self.suiteRenames = suiteRenames
        self.skippedSuites = skippedSuites
    }
}

public final class ArtifactService: @unchecked Sendable {
    private let store: RouterStateStore
    private let codec: VersionedJSONCodec
    private let zip: ZipTool
    private let fileManager: FileManager

    public init(
        store: RouterStateStore,
        codec: VersionedJSONCodec = VersionedJSONCodec(),
        zip: ZipTool = ZipTool(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.codec = codec
        self.zip = zip
        self.fileManager = fileManager
    }

    public func export(
        skillNames selectedNames: Set<SkillName>? = nil,
        to destination: URL
    ) throws -> ArtifactExportResult {
        let state = try store.load()
        let skills = state.skills.filter { selectedNames?.contains($0.name) ?? true }
        guard !skills.isEmpty else { throw SkillRouterError.io("没有可导出的 Skill") }
        let selected = Set(skills.map(\.name))
        let sourceIDs = Set(skills.compactMap(\.sourceID))
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("skill-router-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

        for skill in skills.sorted(by: { $0.name < $1.name }) {
            let source = store.paths.root.appendingPathComponent(skill.contentRelativePath, isDirectory: true)
            let target = temporaryRoot.appendingPathComponent(skill.contentRelativePath, isDirectory: true)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try DirectoryCopier(fileManager: fileManager).copy(from: source, to: target)
        }

        let files = try artifactFileRecords(in: temporaryRoot)
        let suites = state.suites.compactMap { suite -> SkillSuiteRecord? in
            let included = suite.skills.filter { selected.contains($0) }
            guard !included.isEmpty else { return nil }
            return SkillSuiteRecord(
                name: suite.name,
                origin: suite.origin,
                sourceID: suite.sourceID,
                skills: included,
                createdAt: suite.createdAt
            )
        }
        let sources = state.gitSources.compactMap { source -> GitSourceRecord? in
            guard sourceIDs.contains(source.id) else { return nil }
            var value = source
            value.selectedSkills = source.selectedSkills.filter { selected.contains($0) }
            return value
        }
        let manifest = ArtifactManifest(
            skills: skills,
            suites: suites,
            gitSources: sources,
            files: files
        )
        try AtomicFileWriter().write(codec.encode(manifest), to: temporaryRoot.appendingPathComponent("manifest.json"))
        try zip.createDeterministicArchive(contentsOf: temporaryRoot, at: destination)
        return ArtifactExportResult(destination: destination, skillNames: skills.map(\.name).sorted(), fileCount: files.count)
    }

    public func importArtifact(
        from archive: URL,
        options: ArtifactImportOptions = ArtifactImportOptions(),
        now: Date = Date()
    ) throws -> LocalImportResult {
        let extractionRoot = fileManager.temporaryDirectory
            .appendingPathComponent("skill-router-artifact-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: extractionRoot) }
        try zip.extractArchive(archive, to: extractionRoot)
        let manifestURL = extractionRoot.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SkillRouterError.invalidJSON("制品缺少 manifest.json")
        }
        let manifest = try codec.decodeArtifactManifest(Data(contentsOf: manifestURL))
        try verify(manifest: manifest, root: extractionRoot)

        return try CentralTransactionManager(store: store).perform { state, stagedLibrary in
            var imported: [SkillName] = []
            var replaced: [SkillName] = []
            var skipped: [SkillName] = []
            var importedByOriginalSuite: [SuiteName: [SkillName]] = [:]

            for artifactSkill in manifest.skills.sorted(by: { $0.name < $1.name }) {
                if let originalSuite = artifactSkill.suiteName,
                   options.skippedSuites.contains(originalSuite) {
                    skipped.append(artifactSkill.name)
                    continue
                }
                if let existing = state.skill(named: artifactSkill.name) {
                    switch options.skillConflicts[artifactSkill.name] {
                    case .replace:
                        let existingPath = stagedLibrary.appendingPathComponent(String(existing.contentRelativePath.dropFirst("Library/".count)))
                        if fileManager.fileExists(atPath: existingPath.path) { try fileManager.removeItem(at: existingPath) }
                        removeReferences(to: artifactSkill.name, from: &state)
                        replaced.append(artifactSkill.name)
                    case .skip:
                        skipped.append(artifactSkill.name)
                        continue
                    case nil:
                        throw SkillRouterError.unmanagedPathConflict("中央库已存在 Skill：\(artifactSkill.name.rawValue)")
                    }
                }

                let mappedSuite = artifactSkill.suiteName.map { options.suiteRenames[$0] ?? $0 }
                if let mappedSuite,
                   let existingSuite = state.suites.first(where: { $0.name == mappedSuite }),
                   existingSuite.sourceID != artifactSkill.sourceID {
                    throw SkillRouterError.io("套件名称已被其他来源使用：\(mappedSuite.rawValue)")
                }
                let relativePath = mappedSuite.map {
                    "Library/Suites/\($0.rawValue)/\(artifactSkill.name.rawValue)"
                } ?? "Library/Skills/\(artifactSkill.name.rawValue)"
                let source = extractionRoot.appendingPathComponent(artifactSkill.contentRelativePath, isDirectory: true)
                let destination = stagedLibrary.appendingPathComponent(String(relativePath.dropFirst("Library/".count)), isDirectory: true)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try DirectoryCopier(fileManager: fileManager).copy(from: source, to: destination)
                state.skills.append(ManagedSkillRecord(
                    name: artifactSkill.name,
                    origin: artifactSkill.origin,
                    suiteName: mappedSuite,
                    sourceID: artifactSkill.sourceID,
                    contentRelativePath: relativePath,
                    importedAt: now
                ))
                if let originalSuite = artifactSkill.suiteName {
                    importedByOriginalSuite[originalSuite, default: []].append(artifactSkill.name)
                }
                imported.append(artifactSkill.name)
            }

            for suite in manifest.suites {
                let importedSkills = importedByOriginalSuite[suite.name] ?? []
                guard !importedSkills.isEmpty else { continue }
                let mappedName = options.suiteRenames[suite.name] ?? suite.name
                if let index = state.suites.firstIndex(where: { $0.name == mappedName && $0.sourceID == suite.sourceID }) {
                    state.suites[index].skills = Array(Set(state.suites[index].skills + importedSkills)).sorted()
                } else {
                    state.suites.append(SkillSuiteRecord(
                        name: mappedName,
                        origin: suite.origin,
                        sourceID: suite.sourceID,
                        skills: importedSkills,
                        createdAt: now
                    ))
                }
            }

            for source in manifest.gitSources {
                let included = source.selectedSkills.filter { imported.contains($0) }
                guard !included.isEmpty else { continue }
                if let index = state.gitSources.firstIndex(where: { $0.id == source.id }) {
                    state.gitSources[index].selectedSkills = Array(Set(state.gitSources[index].selectedSkills + included)).sorted()
                } else {
                    var restored = source
                    restored.selectedSkills = included
                    if let suiteName = restored.suiteName {
                        restored.suiteName = options.suiteRenames[suiteName] ?? suiteName
                    }
                    state.gitSources.append(restored)
                }
            }

            return LocalImportResult(imported: imported, replaced: replaced, skipped: skipped, suiteName: nil)
        }
    }

    public func inspect(_ archive: URL) throws -> ArtifactManifest {
        let extractionRoot = fileManager.temporaryDirectory
            .appendingPathComponent("skill-router-artifact-inspect-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: extractionRoot) }
        try zip.extractArchive(archive, to: extractionRoot)
        let manifestURL = extractionRoot.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SkillRouterError.invalidJSON("制品缺少 manifest.json")
        }
        let manifest = try codec.decodeArtifactManifest(Data(contentsOf: manifestURL))
        try verify(manifest: manifest, root: extractionRoot)
        return manifest
    }

    private func artifactFileRecords(in root: URL) throws -> [ArtifactFileRecord] {
        var records: [ArtifactFileRecord] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else { return [] }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let relative = try relativePath(of: url, under: root)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                let data = Data(destination.utf8)
                records.append(ArtifactFileRecord(path: relative, kind: .symbolicLink, sha256: sha256(data), byteCount: Int64(data.count)))
            } else if values.isDirectory != true {
                let data = try Data(contentsOf: url)
                records.append(ArtifactFileRecord(path: relative, kind: .file, sha256: sha256(data), byteCount: Int64(data.count)))
            }
        }
        return records.sorted { $0.path < $1.path }
    }

    private func verify(manifest: ArtifactManifest, root: URL) throws {
        let expectedPaths = Set(manifest.files.map(\.path))
        guard expectedPaths.count == manifest.files.count else {
            throw SkillRouterError.invalidArchivePath("制品清单包含重复路径")
        }
        for record in manifest.files {
            try zip.validateEntryPaths([record.path])
            let url = root.appendingPathComponent(record.path)
            let standardized = url.standardizedFileURL.path
            guard standardized.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw SkillRouterError.invalidArchivePath(record.path)
            }
            let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            let data: Data
            switch record.kind {
            case .symbolicLink:
                guard isSymlink else { throw SkillRouterError.invalidArchivePath("条目类型不匹配：\(record.path)") }
                data = Data(try fileManager.destinationOfSymbolicLink(atPath: url.path).utf8)
            case .file:
                guard !isSymlink, fileManager.fileExists(atPath: url.path) else {
                    throw SkillRouterError.invalidArchivePath("文件缺失：\(record.path)")
                }
                data = try Data(contentsOf: url)
            }
            guard Int64(data.count) == record.byteCount, sha256(data) == record.sha256 else {
                throw SkillRouterError.io("制品完整性校验失败：\(record.path)")
            }
        }

        let actual = Set(try artifactFileRecords(in: root).map(\.path)).subtracting(["manifest.json"])
        guard actual == expectedPaths else {
            throw SkillRouterError.io("制品包含清单之外的文件或缺少已声明文件")
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func relativePath(of url: URL, under root: URL) throws -> String {
        let path = url.path
        var candidates = [root.path, root.resolvingSymlinksInPath().path]
        candidates.append(contentsOf: candidates.filter { $0.hasPrefix("/var/") }.map { "/private" + $0 })
        for base in candidates where path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        throw SkillRouterError.io("无法计算制品相对路径：\(path)")
    }

    private func removeReferences(to name: SkillName, from state: inout RouterState) {
        state.skills.removeAll { $0.name == name }
        for index in state.suites.indices { state.suites[index].skills.removeAll { $0 == name } }
        state.suites.removeAll { $0.skills.isEmpty }
        for index in state.gitSources.indices { state.gitSources[index].selectedSkills.removeAll { $0 == name } }
        state.gitSources.removeAll { $0.selectedSkills.isEmpty }
    }
}
