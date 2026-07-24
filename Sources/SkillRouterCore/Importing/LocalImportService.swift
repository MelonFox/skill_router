import Foundation

public enum SkillConflictResolution: String, Codable, CaseIterable, Hashable, Sendable {
    case replace
    case skip
}

public struct LocalImportResult: Equatable, Sendable {
    public let imported: [SkillName]
    public let replaced: [SkillName]
    public let skipped: [SkillName]
    public let suiteName: SuiteName?

    public init(imported: [SkillName], replaced: [SkillName], skipped: [SkillName], suiteName: SuiteName?) {
        self.imported = imported.sorted()
        self.replaced = replaced.sorted()
        self.skipped = skipped.sorted()
        self.suiteName = suiteName
    }
}

public final class LocalImportService: @unchecked Sendable {
    private let discovery: SkillDiscovery
    private let transactions: CentralTransactionManager
    private let store: RouterStateStore
    private let fileManager: FileManager

    public init(
        store: RouterStateStore,
        discovery: SkillDiscovery = SkillDiscovery(),
        fileManager: FileManager = .default,
        failureInjector: CentralTransactionManager.FailureInjector? = nil
    ) {
        self.store = store
        self.discovery = discovery
        self.fileManager = fileManager
        self.transactions = CentralTransactionManager(
            store: store,
            fileManager: fileManager,
            failureInjector: failureInjector
        )
    }

    public func discover(in source: URL) throws -> [SkillCandidate] {
        try discovery.discover(in: source)
    }

    public func importSkills(
        from source: URL,
        selectedNames: Set<SkillName>? = nil,
        suiteName: SuiteName? = nil,
        conflictResolutions: [SkillName: SkillConflictResolution] = [:],
        now: Date = Date()
    ) throws -> LocalImportResult {
        let allCandidates = try discovery.discover(in: source)
        let candidates = allCandidates.filter { selectedNames?.contains($0.name) ?? true }
        guard !candidates.isEmpty else {
            throw SkillRouterError.io("没有选择可导入的 Skill")
        }
        let isSuite = allCandidates.count > 1
        if isSuite, suiteName == nil {
            throw SkillRouterError.invalidSuiteName("")
        }
        if !isSuite, suiteName != nil {
            throw SkillRouterError.io("单个候选必须作为独立 Skill 导入")
        }

        let (result, removedSourceIDs) = try transactions.perform { state, stagedLibrary in
            if let suiteName,
               state.suites.contains(where: { $0.name == suiteName }) {
                throw SkillRouterError.io("套件名称已存在：\(suiteName.rawValue)")
            }

            var imported: [SkillName] = []
            var replaced: [SkillName] = []
            var skipped: [SkillName] = []
            var replacedSourceIDs = Set<UUID>()

            for candidate in candidates {
                if let existing = state.skill(named: candidate.name) {
                    switch conflictResolutions[candidate.name] {
                    case .replace:
                        if let sourceID = existing.sourceID { replacedSourceIDs.insert(sourceID) }
                        try removeExistingContent(existing, from: stagedLibrary)
                        state.skills.removeAll { $0.name == candidate.name }
                        for index in state.suites.indices {
                            state.suites[index].skills.removeAll { $0 == candidate.name }
                        }
                        state.suites.removeAll { $0.skills.isEmpty }
                        for index in state.gitSources.indices {
                            state.gitSources[index].selectedSkills.removeAll { $0 == candidate.name }
                        }
                        state.gitSources.removeAll { $0.selectedSkills.isEmpty }
                        replaced.append(candidate.name)
                    case .skip:
                        skipped.append(candidate.name)
                        continue
                    case nil:
                        throw SkillRouterError.unmanagedPathConflict("中央库已存在 Skill：\(candidate.name.rawValue)")
                    }
                }

                let relativePath: String
                if let suiteName {
                    relativePath = "Library/Suites/\(suiteName.rawValue)/\(candidate.name.rawValue)"
                } else {
                    relativePath = "Library/Skills/\(candidate.name.rawValue)"
                }
                let stagedDestination = stagedLibrary
                    .appendingPathComponent(String(relativePath.dropFirst("Library/".count)), isDirectory: true)
                try fileManager.createDirectory(
                    at: stagedDestination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: stagedDestination.path) {
                    try fileManager.removeItem(at: stagedDestination)
                }
                try fileManager.copyItem(at: candidate.directory, to: stagedDestination)

                state.skills.append(ManagedSkillRecord(
                    name: candidate.name,
                    origin: .local,
                    suiteName: suiteName,
                    sourceID: nil,
                    contentRelativePath: relativePath,
                    importedAt: now
                ))
                imported.append(candidate.name)
            }

            if let suiteName, !imported.isEmpty {
                state.suites.append(SkillSuiteRecord(
                    name: suiteName,
                    origin: .local,
                    sourceID: nil,
                    skills: imported,
                    createdAt: now
                ))
            }

            let retainedSourceIDs = Set(state.gitSources.map(\.id))
            let removedSourceIDs = replacedSourceIDs.subtracting(retainedSourceIDs)
            return (LocalImportResult(
                    imported: imported,
                    replaced: replaced,
                    skipped: skipped,
                    suiteName: imported.isEmpty ? nil : suiteName
                ), removedSourceIDs)
        }
        for sourceID in removedSourceIDs {
            try? fileManager.removeItem(at: store.paths.sourcesDirectory.appendingPathComponent(sourceID.uuidString))
        }
        return result
    }

    private func removeExistingContent(_ skill: ManagedSkillRecord, from stagedLibrary: URL) throws {
        let destination = stagedLibrary
            .appendingPathComponent(String(skill.contentRelativePath.dropFirst("Library/".count)))
        if fileManager.fileExists(atPath: destination.path) ||
            (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try fileManager.removeItem(at: destination)
        }
    }
}
