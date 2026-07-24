import Foundation

public struct UpdateCheckResult: Codable, Equatable, Sendable {
    public let sourceID: UUID
    public let remoteURL: String
    public let updateAvailable: Bool
    public let checkedCommit: String

    public init(sourceID: UUID, remoteURL: String, updateAvailable: Bool, checkedCommit: String) {
        self.sourceID = sourceID
        self.remoteURL = remoteURL
        self.updateAvailable = updateAvailable
        self.checkedCommit = checkedCommit
    }
}

public struct ProjectCascadeFailure: Codable, Equatable, Sendable {
    public let projectPath: String
    public let diagnostic: String
}

public struct AppliedGitUpdate: Codable, Equatable, Sendable {
    public let sourceID: UUID
    public let updated: [SkillName]
    public let removed: [SkillName]
    public let discovered: [SkillName]
    public let projectFailures: [ProjectCascadeFailure]
}

public final class GitUpdateService: @unchecked Sendable {
    private let store: RouterStateStore
    private let git: GitClient
    private let discovery: SkillDiscovery
    private let fileManager: FileManager
    private let allowLocalRemotes: Bool

    public init(
        store: RouterStateStore,
        git: GitClient = GitClient(),
        discovery: SkillDiscovery = SkillDiscovery(),
        fileManager: FileManager = .default,
        allowLocalRemotes: Bool = false
    ) {
        self.store = store
        self.git = git
        self.discovery = discovery
        self.fileManager = fileManager
        self.allowLocalRemotes = allowLocalRemotes
    }

    public func checkForUpdates(force: Bool, now: Date = Date()) throws -> [UpdateCheckResult] {
        let snapshot = try store.load()
        if !force,
           let last = snapshot.lastAutomaticUpdateCheckAt,
           now.timeIntervalSince(last) < 24 * 60 * 60 {
            return snapshot.gitSources.map {
                UpdateCheckResult(
                    sourceID: $0.id,
                    remoteURL: $0.remoteURL,
                    updateAvailable: $0.availableCommit != nil,
                    checkedCommit: $0.availableCommit ?? $0.lastAppliedCommit
                )
            }
        }

        let checks = try snapshot.gitSources.map { source -> UpdateCheckResult in
            try validateRemote(source.remoteURL)
            let head = try git.remoteHead(source.remoteURL)
            return UpdateCheckResult(
                sourceID: source.id,
                remoteURL: source.remoteURL,
                updateAvailable: head != source.lastAppliedCommit,
                checkedCommit: head
            )
        }
        try store.withExclusiveState { state in
            for check in checks {
                guard let index = state.gitSources.firstIndex(where: { $0.id == check.sourceID }) else { continue }
                state.gitSources[index].availableCommit = check.updateAvailable ? check.checkedCommit : nil
                state.gitSources[index].lastCheckedAt = now
            }
            if !force { state.lastAutomaticUpdateCheckAt = now }
        }
        return checks
    }

    public func applyUpdate(sourceID: UUID, now: Date = Date()) throws -> AppliedGitUpdate {
        let snapshot = try store.load()
        guard let source = snapshot.gitSources.first(where: { $0.id == sourceID }) else {
            throw SkillRouterError.io("Git 来源不存在：\(sourceID)")
        }
        try validateRemote(source.remoteURL)
        let updateDirectory = store.paths.stagingDirectory
            .appendingPathComponent("git-update-\(UUID().uuidString)", isDirectory: true)
        let repository = updateDirectory.appendingPathComponent("repository", isDirectory: true)
        try fileManager.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: updateDirectory) }

        try git.cloneDefaultBranchMetadata(from: source.remoteURL, to: repository)
        let commit = try git.headCommit(in: repository)
        let candidates = try GitTreeSkillDiscovery(git: git).discover(in: repository)
        let candidatesByName = Dictionary(uniqueKeysWithValues: candidates.map { ($0.name, $0) })
        let selected = Set(source.selectedSkills)
        let presentSelected = source.selectedSkills.filter { candidatesByName[$0] != nil }
        let removed = source.selectedSkills.filter { candidatesByName[$0] == nil }
        let discovered = candidates.map(\.name).filter { !selected.contains($0) }.sorted()
        try git.checkout(
            paths: presentSelected.compactMap { candidatesByName[$0]?.relativeDirectory },
            in: repository
        )

        let updated: [SkillName] = try CentralTransactionManager(store: store).perform { state, stagedLibrary in
            guard let sourceIndex = state.gitSources.firstIndex(where: { $0.id == sourceID }) else {
                throw SkillRouterError.io("Git 来源在更新过程中被移除")
            }
            for name in presentSelected {
                guard let candidate = candidatesByName[name],
                      let skillIndex = state.skills.firstIndex(where: { $0.name == name && $0.sourceID == sourceID }) else {
                    continue
                }
                let record = state.skills[skillIndex]
                let destination = stagedLibrary.appendingPathComponent(String(record.contentRelativePath.dropFirst("Library/".count)))
                if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                try DirectoryCopier(fileManager: fileManager).copy(
                    from: repository.appendingPathComponent(candidate.relativeDirectory, isDirectory: true),
                    to: destination,
                    excludingNames: [".git", ".hg", ".svn"]
                )
            }
            for name in removed {
                if let record = state.skills.first(where: { $0.name == name && $0.sourceID == sourceID }) {
                    let destination = stagedLibrary.appendingPathComponent(String(record.contentRelativePath.dropFirst("Library/".count)))
                    if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
                }
                state.skills.removeAll { $0.name == name && $0.sourceID == sourceID }
                for index in state.suites.indices { state.suites[index].skills.removeAll { $0 == name } }
            }
            state.suites.removeAll { $0.skills.isEmpty }
            state.gitSources[sourceIndex].selectedSkills = presentSelected
            state.gitSources[sourceIndex].lastAppliedCommit = commit
            state.gitSources[sourceIndex].availableCommit = nil
            state.gitSources[sourceIndex].lastCheckedAt = now
            return presentSelected.sorted()
        }

        try replaceCachedRepository(sourceID: sourceID, with: repository)
        let failures = cascadeRemovedSkills(removed)
        return AppliedGitUpdate(
            sourceID: sourceID,
            updated: updated,
            removed: removed.sorted(),
            discovered: discovered,
            projectFailures: failures
        )
    }

    private func cascadeRemovedSkills(_ removed: [SkillName]) -> [ProjectCascadeFailure] {
        guard !removed.isEmpty, let projects = try? store.load().projects else { return [] }
        let projectService = ProjectService(store: store, fileManager: fileManager)
        var failures: [ProjectCascadeFailure] = []
        for project in projects {
            do {
                _ = try projectService.uninstall(
                    skillNames: removed,
                    project: URL(fileURLWithPath: project.path, isDirectory: true)
                )
            } catch {
                failures.append(ProjectCascadeFailure(projectPath: project.path, diagnostic: error.localizedDescription))
            }
        }
        return failures
    }

    private func replaceCachedRepository(sourceID: UUID, with repository: URL) throws {
        let sourceDirectory = store.paths.sourcesDirectory.appendingPathComponent(sourceID.uuidString, isDirectory: true)
        let destination = sourceDirectory.appendingPathComponent("repository", isDirectory: true)
        let temporary = sourceDirectory.appendingPathComponent("repository.new", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: temporary.path) { try fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: repository, to: temporary)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private func validateRemote(_ remote: String) throws {
        if allowLocalRemotes, remote.hasPrefix("/") || remote.hasPrefix("file://") { return }
        guard let scheme = URL(string: remote)?.scheme?.lowercased(),
              ["https", "http", "git"].contains(scheme),
              !remote.contains("@") else {
            throw SkillRouterError.io("首版只支持无需凭据的公开 Git URL")
        }
    }
}
