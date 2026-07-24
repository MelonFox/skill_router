import Foundation

public struct CentralDeletionResult: Codable, Equatable, Sendable {
    public let deleted: [SkillName]
    public let missing: [SkillName]
    public let projectFailures: [ProjectCascadeFailure]

    public init(deleted: [SkillName], missing: [SkillName], projectFailures: [ProjectCascadeFailure]) {
        self.deleted = deleted.sorted()
        self.missing = missing.sorted()
        self.projectFailures = projectFailures
    }
}

public struct SuiteRenameResult: Codable, Equatable, Sendable {
    public let oldName: SuiteName
    public let newName: SuiteName
    public let skills: [SkillName]

    public init(oldName: SuiteName, newName: SuiteName, skills: [SkillName]) {
        self.oldName = oldName
        self.newName = newName
        self.skills = skills.sorted()
    }
}

public final class CentralLibraryService: @unchecked Sendable {
    private let store: RouterStateStore
    private let fileManager: FileManager

    public init(store: RouterStateStore, fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    public func state() throws -> RouterState {
        try store.load()
    }

    public func delete(skillNames: [SkillName]) throws -> CentralDeletionResult {
        let requested = Array(Set(skillNames)).sorted()
        let before = try store.load()
        let existing = Set(before.skills.map(\.name))
        let deleted = requested.filter { existing.contains($0) }
        let missing = requested.filter { !existing.contains($0) }
        guard !deleted.isEmpty else {
            return CentralDeletionResult(deleted: [], missing: missing, projectFailures: [])
        }

        let sourceIDsBefore = Set(before.gitSources.map(\.id))
        try CentralTransactionManager(store: store).perform { state, stagedLibrary in
            for name in deleted {
                if let record = state.skills.first(where: { $0.name == name }) {
                    let destination = stagedLibrary.appendingPathComponent(
                        String(record.contentRelativePath.dropFirst("Library/".count))
                    )
                    if fileManager.fileExists(atPath: destination.path) {
                        try fileManager.removeItem(at: destination)
                    }
                }
                state.skills.removeAll { $0.name == name }
                for index in state.suites.indices { state.suites[index].skills.removeAll { $0 == name } }
                for index in state.gitSources.indices { state.gitSources[index].selectedSkills.removeAll { $0 == name } }
            }
            state.suites.removeAll { $0.skills.isEmpty }
            state.gitSources.removeAll { $0.selectedSkills.isEmpty }
        }

        let after = try store.load()
        let remainingSourceIDs = Set(after.gitSources.map(\.id))
        for removedID in sourceIDsBefore.subtracting(remainingSourceIDs) {
            try? fileManager.removeItem(at: store.paths.sourcesDirectory.appendingPathComponent(removedID.uuidString))
        }
        let failures = cascade(deleted, through: after.projects)
        return CentralDeletionResult(deleted: deleted, missing: missing, projectFailures: failures)
    }

    public func renameSuite(from oldName: SuiteName, to newName: SuiteName) throws -> SuiteRenameResult {
        guard oldName != newName else {
            throw SkillRouterError.io("新套件名称必须与原名称不同")
        }

        return try CentralTransactionManager(store: store, fileManager: fileManager).perform { state, stagedLibrary in
            guard let suite = state.suites.first(where: { $0.name == oldName }) else {
                throw SkillRouterError.io("套件不存在：\(oldName.rawValue)")
            }
            guard !state.suites.contains(where: { $0.name == newName }) else {
                throw SkillRouterError.io("套件名称已存在：\(newName.rawValue)")
            }

            let oldDirectory = stagedLibrary.appendingPathComponent("Suites/\(oldName.rawValue)", isDirectory: true)
            let newDirectory = stagedLibrary.appendingPathComponent("Suites/\(newName.rawValue)", isDirectory: true)
            guard fileManager.fileExists(atPath: oldDirectory.path) else {
                throw SkillRouterError.io("套件内容目录不存在：\(oldDirectory.path)")
            }
            try fileManager.moveItem(at: oldDirectory, to: newDirectory)

            state.suites.removeAll { $0.name == oldName }
            state.suites.append(SkillSuiteRecord(
                name: newName,
                origin: suite.origin,
                sourceID: suite.sourceID,
                skills: suite.skills,
                createdAt: suite.createdAt
            ))
            state.skills = state.skills.map { skill in
                guard skill.suiteName == oldName else { return skill }
                return ManagedSkillRecord(
                    name: skill.name,
                    origin: skill.origin,
                    suiteName: newName,
                    sourceID: skill.sourceID,
                    contentRelativePath: "Library/Suites/\(newName.rawValue)/\(skill.name.rawValue)",
                    importedAt: skill.importedAt
                )
            }
            for index in state.gitSources.indices where state.gitSources[index].suiteName == oldName {
                state.gitSources[index].suiteName = newName
            }
            return SuiteRenameResult(oldName: oldName, newName: newName, skills: suite.skills)
        }
    }

    private func cascade(
        _ deleted: [SkillName],
        through projects: [RegisteredProjectRecord]
    ) -> [ProjectCascadeFailure] {
        let projectService = ProjectService(store: store, fileManager: fileManager)
        var failures: [ProjectCascadeFailure] = []
        for project in projects {
            do {
                _ = try projectService.uninstall(
                    skillNames: deleted,
                    project: URL(fileURLWithPath: project.path, isDirectory: true)
                )
            } catch {
                failures.append(ProjectCascadeFailure(
                    projectPath: project.path,
                    diagnostic: error.localizedDescription
                ))
            }
        }
        return failures
    }
}
