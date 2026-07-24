import Foundation

public struct PreparedGitImportCandidate: Equatable, Sendable {
    public let name: SkillName
    public let relativeDirectory: String
}

public struct PreparedGitImport: Equatable, Sendable {
    public let id: UUID
    public let sourceID: UUID
    public let remoteURL: String
    public let repository: URL
    public let commit: String
    public let candidates: [PreparedGitImportCandidate]
    public let stagingDirectory: URL

    public var defaultSuiteName: String {
        let withoutSlash = remoteURL.hasSuffix("/") ? String(remoteURL.dropLast()) : remoteURL
        let component = URL(string: withoutSlash)?.lastPathComponent
            ?? URL(fileURLWithPath: withoutSlash).lastPathComponent
        let name = component.hasSuffix(".git") ? String(component.dropLast(4)) : component
        return name.isEmpty ? "git-suite" : name
    }
}

public final class GitImportService: @unchecked Sendable {
    private let store: RouterStateStore
    private let discovery: SkillDiscovery
    private let git: GitClient
    private let fileManager: FileManager
    private let allowLocalRemotes: Bool

    public init(
        store: RouterStateStore,
        discovery: SkillDiscovery = SkillDiscovery(),
        git: GitClient = GitClient(),
        fileManager: FileManager = .default,
        allowLocalRemotes: Bool = false
    ) {
        self.store = store
        self.discovery = discovery
        self.git = git
        self.fileManager = fileManager
        self.allowLocalRemotes = allowLocalRemotes
    }

    public func prepare(remoteURL: String) throws -> PreparedGitImport {
        try validateRemote(remoteURL)
        try store.initializeIfNeeded()
        let id = UUID()
        let sourceID = UUID()
        let stagingDirectory = store.paths.stagingDirectory
            .appendingPathComponent("git-import-\(id.uuidString)", isDirectory: true)
        let repository = stagingDirectory.appendingPathComponent("repository", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        do {
            try git.cloneDefaultBranchMetadata(from: remoteURL, to: repository)
            let commit = try git.headCommit(in: repository)
            let discovered = try GitTreeSkillDiscovery(git: git).discover(in: repository)
            guard !discovered.isEmpty else {
                throw SkillRouterError.io("Git 来源中没有候选 Skill")
            }
            let candidates = discovered.map { candidate in
                PreparedGitImportCandidate(
                    name: candidate.name,
                    relativeDirectory: candidate.relativeDirectory
                )
            }
            return PreparedGitImport(
                id: id,
                sourceID: sourceID,
                remoteURL: remoteURL,
                repository: repository,
                commit: commit,
                candidates: candidates,
                stagingDirectory: stagingDirectory
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    public func cancel(_ prepared: PreparedGitImport) {
        try? fileManager.removeItem(at: prepared.stagingDirectory)
    }

    public func commit(
        _ prepared: PreparedGitImport,
        selectedNames: Set<SkillName>? = nil,
        suiteName requestedSuiteName: SuiteName? = nil,
        conflictResolutions: [SkillName: SkillConflictResolution] = [:],
        now: Date = Date()
    ) throws -> LocalImportResult {
        let selectedCandidates = prepared.candidates.filter { selectedNames?.contains($0.name) ?? true }
        guard !selectedCandidates.isEmpty else {
            throw SkillRouterError.io("没有选择可导入的 Skill")
        }
        let isSuite = prepared.candidates.count > 1
        let suiteName: SuiteName?
        if isSuite {
            suiteName = try requestedSuiteName ?? SuiteName(rawValue: prepared.defaultSuiteName)
        } else {
            guard requestedSuiteName == nil else {
                throw SkillRouterError.io("单个候选必须作为独立 Skill 导入")
            }
            suiteName = nil
        }

        // Git 候选只能提交一次。先原子移动暂存目录，避免双击产生的两个任务
        // 同时消费同一仓库，随后又互相删除来源目录。
        let claimedStagingDirectory = store.paths.stagingDirectory
            .appendingPathComponent("git-commit-\(prepared.id.uuidString)", isDirectory: true)
        do {
            try fileManager.moveItem(at: prepared.stagingDirectory, to: claimedStagingDirectory)
        } catch {
            throw SkillRouterError.io("Git 候选已被提交或失效，请重新读取候选")
        }
        let claimedRepository = claimedStagingDirectory
            .appendingPathComponent("repository", isDirectory: true)

        let sourceDirectory = store.paths.sourcesDirectory
            .appendingPathComponent(prepared.sourceID.uuidString, isDirectory: true)
        let finalRepository = sourceDirectory.appendingPathComponent("repository", isDirectory: true)
        do {
            try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            try git.checkout(
                paths: selectedCandidates.map(\.relativeDirectory),
                in: claimedRepository
            )
            try fileManager.moveItem(at: claimedRepository, to: finalRepository)
            try? fileManager.removeItem(at: claimedStagingDirectory)
            let result = try importFromRepository(
                finalRepository,
                prepared: prepared,
                candidates: selectedCandidates,
                suiteName: suiteName,
                conflictResolutions: conflictResolutions,
                now: now
            )
            if result.imported.isEmpty { try? fileManager.removeItem(at: sourceDirectory) }
            return result
        } catch {
            try? fileManager.removeItem(at: sourceDirectory)
            try? fileManager.removeItem(at: claimedStagingDirectory)
            throw error
        }
    }

    public func importSkills(
        from remoteURL: String,
        selectedNames: Set<SkillName>? = nil,
        suiteName: SuiteName? = nil,
        conflictResolutions: [SkillName: SkillConflictResolution] = [:],
        now: Date = Date()
    ) throws -> LocalImportResult {
        let prepared = try prepare(remoteURL: remoteURL)
        return try commit(
            prepared,
            selectedNames: selectedNames,
            suiteName: suiteName,
            conflictResolutions: conflictResolutions,
            now: now
        )
    }

    private func importFromRepository(
        _ repository: URL,
        prepared: PreparedGitImport,
        candidates: [PreparedGitImportCandidate],
        suiteName: SuiteName?,
        conflictResolutions: [SkillName: SkillConflictResolution],
        now: Date
    ) throws -> LocalImportResult {
        try CentralTransactionManager(store: store).perform { state, stagedLibrary in
            if let suiteName,
               state.suites.contains(where: { $0.name == suiteName }) {
                throw SkillRouterError.io("套件名称已被其他来源使用：\(suiteName.rawValue)")
            }
            var imported: [SkillName] = []
            var replaced: [SkillName] = []
            var skipped: [SkillName] = []

            for candidate in candidates {
                if let existing = state.skill(named: candidate.name) {
                    switch conflictResolutions[candidate.name] {
                    case .replace:
                        try removeSkill(existing, from: stagedLibrary)
                        removeReferences(to: candidate.name, from: &state)
                        replaced.append(candidate.name)
                    case .skip:
                        skipped.append(candidate.name)
                        continue
                    case nil:
                        throw SkillRouterError.unmanagedPathConflict("中央库已存在 Skill：\(candidate.name.rawValue)")
                    }
                }
                let relativePath = suiteName.map {
                    "Library/Suites/\($0.rawValue)/\(candidate.name.rawValue)"
                } ?? "Library/Skills/\(candidate.name.rawValue)"
                let destination = stagedLibrary.appendingPathComponent(
                    String(relativePath.dropFirst("Library/".count)),
                    isDirectory: true
                )
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try DirectoryCopier(fileManager: fileManager).copy(
                    from: repository.appendingPathComponent(candidate.relativeDirectory, isDirectory: true),
                    to: destination,
                    excludingNames: [".git", ".hg", ".svn"]
                )
                state.skills.append(ManagedSkillRecord(
                    name: candidate.name,
                    origin: .git,
                    suiteName: suiteName,
                    sourceID: prepared.sourceID,
                    contentRelativePath: relativePath,
                    importedAt: now
                ))
                imported.append(candidate.name)
            }

            if let suiteName, !imported.isEmpty {
                state.suites.append(SkillSuiteRecord(
                    name: suiteName,
                    origin: .git,
                    sourceID: prepared.sourceID,
                    skills: imported,
                    createdAt: now
                ))
            }
            if !imported.isEmpty {
                state.gitSources.append(GitSourceRecord(
                    id: prepared.sourceID,
                    remoteURL: prepared.remoteURL,
                    suiteName: suiteName,
                    selectedSkills: imported,
                    lastAppliedCommit: prepared.commit,
                    lastCheckedAt: now
                ))
            }
            return LocalImportResult(
                imported: imported,
                replaced: replaced,
                skipped: skipped,
                suiteName: imported.isEmpty ? nil : suiteName
            )
        }
    }

    private func validateRemote(_ remote: String) throws {
        if allowLocalRemotes, remote.hasPrefix("/") || remote.hasPrefix("file://") { return }
        guard let scheme = URL(string: remote)?.scheme?.lowercased(),
              ["https", "http", "git"].contains(scheme),
              !remote.contains("@") else {
            throw SkillRouterError.io("首版只支持无需凭据的公开 Git URL")
        }
    }

    private func relativePath(of url: URL, under root: URL) throws -> String {
        if url.standardizedFileURL == root.standardizedFileURL { return "." }
        let path = url.path
        var bases = [root.path, root.resolvingSymlinksInPath().path]
        bases.append(contentsOf: bases.filter { $0.hasPrefix("/var/") }.map { "/private" + $0 })
        for base in bases where path.hasPrefix(base + "/") {
            return String(path.dropFirst(base.count + 1))
        }
        throw SkillRouterError.io("无法计算 Git 候选相对路径：\(path)")
    }

    private func removeSkill(_ skill: ManagedSkillRecord, from stagedLibrary: URL) throws {
        let destination = stagedLibrary.appendingPathComponent(String(skill.contentRelativePath.dropFirst("Library/".count)))
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
    }

    private func removeReferences(to name: SkillName, from state: inout RouterState) {
        state.skills.removeAll { $0.name == name }
        for index in state.suites.indices { state.suites[index].skills.removeAll { $0 == name } }
        state.suites.removeAll { $0.skills.isEmpty }
        for index in state.gitSources.indices { state.gitSources[index].selectedSkills.removeAll { $0 == name } }
        state.gitSources.removeAll { $0.selectedSkills.isEmpty }
    }
}
