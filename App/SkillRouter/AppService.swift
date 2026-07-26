import Foundation
import SkillRouterCore

struct SkillListItem: Identifiable, Equatable, Sendable {
    let record: ManagedSkillRecord
    let description: String

    var id: SkillName { record.name }
    var name: SkillName { record.name }
    var sourceLabel: String {
        switch record.origin {
        case .local: "本地 Skill"
        case .git: "Git 来源"
        }
    }
}

struct ProjectListItem: Identifiable, Equatable, Sendable {
    let path: String
    let skillCount: Int
    let targetCount: Int
    let conflictCount: Int
    let diagnostic: String?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String { url.lastPathComponent }
}

struct DashboardSnapshot: Sendable {
    let state: RouterState
    let skills: [SkillListItem]
    let projects: [ProjectListItem]
}

struct ProjectSnapshot: Sendable {
    let manifest: ProjectManifest
    let reconciliation: ReconciliationReport
}

protocol SkillRouterAppServicing: Sendable {
    func bootstrap(appExecutable: URL?) async throws -> SystemSkillInstallResult
    func loadDashboard() async throws -> DashboardSnapshot
    func discoverLocal(_ source: URL) async throws -> [SkillCandidate]
    func importLocal(
        source: URL,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String
    func prepareGit(_ remoteURL: String) async throws -> PreparedGitImport
    func cancelGit(_ prepared: PreparedGitImport)
    func commitGit(
        _ prepared: PreparedGitImport,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String
    func deleteSkill(_ name: SkillName) async throws -> String
    func renameSuite(from oldName: SuiteName, to newNameText: String) async throws -> String
    func registerProject(_ project: URL, targets: [(String, DistributionTargetRecord)]) async throws -> String
    func unregisterProject(_ project: URL) async throws -> String
    func install(
        names: [SkillName],
        project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async throws -> String
    func uninstallAll(project: URL) async throws -> String
    func uninstall(name: SkillName, project: URL, targetID: String?) async throws -> String
    func gitIgnoreEntries(project: URL) async throws -> [String]
    func addGitIgnoreEntries(project: URL) async throws -> String
    func checkUpdates(force: Bool) async throws -> [UpdateCheckResult]
    func applyUpdate(sourceID: UUID) async throws -> String
    func projectSnapshot(_ project: URL) async throws -> ProjectSnapshot
    func referencingProjects(skillName: SkillName) async -> [String]
    func exportArtifact(names: Set<SkillName>?, destination: URL) async throws -> String
    func inspectArtifact(_ archive: URL) async throws -> ArtifactManifest
    func importArtifact(
        _ archive: URL,
        skillConflicts: [SkillName: SkillConflictResolution],
        suiteRenames: [SuiteName: SuiteName],
        skippedSuites: Set<SuiteName>
    ) async throws -> String
    func setSystemSkill(enabled: Bool, agent: String) async throws -> String
}

enum AppServiceError: LocalizedError {
    case unsupported

    var errorDescription: String? { "当前服务未实现此操作" }
}

extension SkillRouterAppServicing {
    func bootstrap(appExecutable: URL?) async throws -> SystemSkillInstallResult { throw AppServiceError.unsupported }
    func loadDashboard() async throws -> DashboardSnapshot { throw AppServiceError.unsupported }
    func discoverLocal(_ source: URL) async throws -> [SkillCandidate] { throw AppServiceError.unsupported }
    func importLocal(
        source: URL,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String { throw AppServiceError.unsupported }
    func prepareGit(_ remoteURL: String) async throws -> PreparedGitImport { throw AppServiceError.unsupported }
    func cancelGit(_ prepared: PreparedGitImport) {}
    func commitGit(
        _ prepared: PreparedGitImport,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String { throw AppServiceError.unsupported }
    func deleteSkill(_ name: SkillName) async throws -> String { throw AppServiceError.unsupported }
    func renameSuite(from oldName: SuiteName, to newNameText: String) async throws -> String { throw AppServiceError.unsupported }
    func registerProject(_ project: URL, targets: [(String, DistributionTargetRecord)]) async throws -> String { throw AppServiceError.unsupported }
    func unregisterProject(_ project: URL) async throws -> String { throw AppServiceError.unsupported }
    func install(
        names: [SkillName],
        project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async throws -> String { throw AppServiceError.unsupported }
    func uninstallAll(project: URL) async throws -> String { throw AppServiceError.unsupported }
    func uninstall(name: SkillName, project: URL, targetID: String?) async throws -> String { throw AppServiceError.unsupported }
    func gitIgnoreEntries(project: URL) async throws -> [String] { throw AppServiceError.unsupported }
    func addGitIgnoreEntries(project: URL) async throws -> String { throw AppServiceError.unsupported }
    func checkUpdates(force: Bool) async throws -> [UpdateCheckResult] { throw AppServiceError.unsupported }
    func applyUpdate(sourceID: UUID) async throws -> String { throw AppServiceError.unsupported }
    func projectSnapshot(_ project: URL) async throws -> ProjectSnapshot { throw AppServiceError.unsupported }
    func referencingProjects(skillName: SkillName) async -> [String] { [] }
    func exportArtifact(names: Set<SkillName>?, destination: URL) async throws -> String { throw AppServiceError.unsupported }
    func inspectArtifact(_ archive: URL) async throws -> ArtifactManifest { throw AppServiceError.unsupported }
    func importArtifact(
        _ archive: URL,
        skillConflicts: [SkillName: SkillConflictResolution],
        suiteRenames: [SuiteName: SuiteName],
        skippedSuites: Set<SuiteName>
    ) async throws -> String { throw AppServiceError.unsupported }
    func setSystemSkill(enabled: Bool, agent: String) async throws -> String { throw AppServiceError.unsupported }
}

struct LiveAppService: SkillRouterAppServicing {
    let paths: RouterPaths
    let environment: [String: String]
    let homeDirectory: URL

    func bootstrap(appExecutable: URL?) async throws -> SystemSkillInstallResult {
        try await Task.detached { [environment, homeDirectory] in
            let result = try BootstrapService().bootstrap(
                environment: environment,
                homeDirectory: homeDirectory,
                appExecutable: appExecutable
            )
            let store = RouterStateStore(paths: paths)
            let service = ProjectService(store: store)
            for project in (try? service.registeredProjects()) ?? [] {
                _ = try? service.reconcile(project: URL(fileURLWithPath: project.path, isDirectory: true))
            }
            return result
        }.value
    }

    func loadDashboard() async throws -> DashboardSnapshot {
        try await Task.detached {
            let store = RouterStateStore(paths: paths)
            let state = try store.load()
            let parser = SkillManifestParser()
            let skills = state.skills.map { record in
                let manifestURL = paths.root
                    .appendingPathComponent(record.contentRelativePath, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                let rawDescription = (try? parser.parse(fileAt: manifestURL).frontmatter["description"])?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = record.origin == .git ? "从 Git 来源导入的 Skill。" : "从本地目录导入的 Skill。"
                return SkillListItem(
                    record: record,
                    description: rawDescription?.replacingOccurrences(of: "\n", with: " ").nilIfEmpty ?? fallback
                )
            }
            let projectService = ProjectService(store: store)
            let projects = state.projects.map { record -> ProjectListItem in
                let url = URL(fileURLWithPath: record.path, isDirectory: true)
                do {
                    let manifest = try ProjectManifestStore().load(from: url)
                    let report = try projectService.reconcile(project: url)
                    return ProjectListItem(
                        path: record.path,
                        skillCount: manifest.skills.count,
                        targetCount: manifest.targets.count,
                        conflictCount: report.items.filter { $0.status == .conflict || $0.status == .missingCentralSkill }.count,
                        diagnostic: nil
                    )
                } catch {
                    return ProjectListItem(
                        path: record.path,
                        skillCount: 0,
                        targetCount: 0,
                        conflictCount: 1,
                        diagnostic: error.localizedDescription
                    )
                }
            }
            return DashboardSnapshot(state: state, skills: skills, projects: projects)
        }.value
    }

    func discoverLocal(_ source: URL) async throws -> [SkillCandidate] {
        try await Task.detached { try SkillDiscovery().discover(in: source) }.value
    }

    func importLocal(
        source: URL,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String {
        try await Task.detached {
            let suite = try suiteName.map(SuiteName.init(rawValue:))
            let result = try LocalImportService(store: RouterStateStore(paths: paths)).importSkills(
                from: source,
                selectedNames: selected,
                suiteName: suite,
                conflictResolutions: conflicts
            )
            return "已导入 \(result.imported.count) 个 Skill"
        }.value
    }

    func prepareGit(_ remoteURL: String) async throws -> PreparedGitImport {
        try await Task.detached {
            try GitImportService(store: RouterStateStore(paths: paths)).prepare(remoteURL: remoteURL)
        }.value
    }

    func cancelGit(_ prepared: PreparedGitImport) {
        GitImportService(store: RouterStateStore(paths: paths)).cancel(prepared)
    }

    func commitGit(
        _ prepared: PreparedGitImport,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String {
        try await Task.detached {
            let suite = try suiteName.map(SuiteName.init(rawValue:))
            let result = try GitImportService(store: RouterStateStore(paths: paths)).commit(
                prepared,
                selectedNames: selected,
                suiteName: suite,
                conflictResolutions: conflicts
            )
            return "已从 Git 导入 \(result.imported.count) 个 Skill"
        }.value
    }

    func deleteSkill(_ name: SkillName) async throws -> String {
        try await Task.detached {
            let result = try CentralLibraryService(store: RouterStateStore(paths: paths)).delete(skillNames: [name])
            if result.projectFailures.isEmpty { return "已删除 \(result.deleted.count) 个 Skill" }
            return "中央 Skill 已删除，\(result.projectFailures.count) 个项目需要手动协调"
        }.value
    }

    func renameSuite(from oldName: SuiteName, to newNameText: String) async throws -> String {
        try await Task.detached {
            let newName = try SuiteName(rawValue: newNameText)
            let result = try CentralLibraryService(store: RouterStateStore(paths: paths)).renameSuite(from: oldName, to: newName)
            return "已将套件 \(result.oldName.rawValue) 重命名为 \(result.newName.rawValue)"
        }.value
    }

    func registerProject(_ project: URL, targets: [(String, DistributionTargetRecord)]) async throws -> String {
        try await Task.detached {
            let service = ProjectService(store: RouterStateStore(paths: paths))
            if targets.isEmpty {
                _ = try service.register(project: project)
            } else {
                for (id, target) in targets { _ = try service.register(project: project, targetID: id, target: target) }
            }
            return "已注册项目：\(project.path)"
        }.value
    }

    func unregisterProject(_ project: URL) async throws -> String {
        try await Task.detached {
            try ProjectService(store: RouterStateStore(paths: paths)).unregister(project: project)
            return "已取消注册：\(project.path)；项目清单和链接保持不变"
        }.value
    }

    func install(
        names: [SkillName],
        project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async throws -> String {
        try await Task.detached {
            let service = ProjectService(store: RouterStateStore(paths: paths))
            var partial = false
            for (id, target) in targets {
                partial = try service.install(skillNames: names, project: project, targetID: id, target: target).isPartial || partial
            }
            return partial ? "安装请求部分完成，请查看项目冲突" : "项目 Skill 已协调"
        }.value
    }

    func uninstallAll(project: URL) async throws -> String {
        try await Task.detached {
            _ = try ProjectService(store: RouterStateStore(paths: paths)).uninstallAll(project: project)
            return "已卸载项目中的全部受管 Skill，项目和目标仍保留"
        }.value
    }

    func uninstall(name: SkillName, project: URL, targetID: String?) async throws -> String {
        try await Task.detached {
            _ = try ProjectService(store: RouterStateStore(paths: paths)).uninstall(
                skillNames: [name], project: project, targetID: targetID
            )
            if let targetID { return "已从目标 \(targetID) 卸载 \(name.rawValue)" }
            return "已从项目卸载 \(name.rawValue)"
        }.value
    }

    func gitIgnoreEntries(project: URL) async throws -> [String] {
        try await Task.detached {
            try ProjectService(store: RouterStateStore(paths: paths)).gitIgnoreEntries(project: project)
        }.value
    }

    func addGitIgnoreEntries(project: URL) async throws -> String {
        try await Task.detached {
            let added = try ProjectService(store: RouterStateStore(paths: paths)).addGitIgnoreEntries(project: project)
            return added.isEmpty ? ".gitignore 已包含全部建议" : "已向 .gitignore 添加 \(added.count) 条忽略项"
        }.value
    }

    func checkUpdates(force: Bool) async throws -> [UpdateCheckResult] {
        try await Task.detached {
            try GitUpdateService(store: RouterStateStore(paths: paths)).checkForUpdates(force: force)
        }.value
    }

    func applyUpdate(sourceID: UUID) async throws -> String {
        try await Task.detached {
            let result = try GitUpdateService(store: RouterStateStore(paths: paths)).applyUpdate(sourceID: sourceID)
            var message = "已更新 \(result.updated.count) 个 Skill"
            if !result.removed.isEmpty { message += "，删除 \(result.removed.count) 个上游已移除 Skill" }
            if !result.discovered.isEmpty { message += "，发现 \(result.discovered.count) 个新候选" }
            if !result.projectFailures.isEmpty { message += "；\(result.projectFailures.count) 个项目需要手动协调" }
            return message
        }.value
    }

    func projectSnapshot(_ project: URL) async throws -> ProjectSnapshot {
        try await Task.detached {
            let store = RouterStateStore(paths: paths)
            return ProjectSnapshot(
                manifest: try ProjectManifestStore().load(from: project),
                reconciliation: try ProjectService(store: store).reconcile(project: project)
            )
        }.value
    }

    func referencingProjects(skillName: SkillName) async -> [String] {
        await Task.detached {
            let service = ProjectService(store: RouterStateStore(paths: paths))
            guard let projects = try? service.registeredProjects() else { return [] }
            return projects.compactMap { project in
                let url = URL(fileURLWithPath: project.path, isDirectory: true)
                guard let manifest = try? ProjectManifestStore().load(from: url),
                      manifest.skills[skillName.rawValue] != nil else { return nil }
                return project.path
            }.sorted()
        }.value
    }

    func exportArtifact(names: Set<SkillName>?, destination: URL) async throws -> String {
        try await Task.detached {
            let result = try ArtifactService(store: RouterStateStore(paths: paths)).export(skillNames: names, to: destination)
            return "已导出 \(result.skillNames.count) 个 Skill：\(result.destination.path)"
        }.value
    }

    func inspectArtifact(_ archive: URL) async throws -> ArtifactManifest {
        try await Task.detached {
            try ArtifactService(store: RouterStateStore(paths: paths)).inspect(archive)
        }.value
    }

    func importArtifact(
        _ archive: URL,
        skillConflicts: [SkillName: SkillConflictResolution],
        suiteRenames: [SuiteName: SuiteName],
        skippedSuites: Set<SuiteName>
    ) async throws -> String {
        try await Task.detached {
            let result = try ArtifactService(store: RouterStateStore(paths: paths)).importArtifact(
                from: archive,
                options: ArtifactImportOptions(
                    skillConflicts: skillConflicts,
                    suiteRenames: suiteRenames,
                    skippedSuites: skippedSuites
                )
            )
            return "已从制品导入 \(result.imported.count) 个 Skill"
        }.value
    }

    func setSystemSkill(enabled: Bool, agent: String) async throws -> String {
        try await Task.detached {
            let result = try SystemSkillInstaller(paths: paths, homeDirectory: homeDirectory).setEnabled(enabled, agent: agent)
            try RouterStateStore(paths: paths).withExclusiveState { state in
                switch agent {
                case "codex": state.systemSkill.codexEnabled = enabled
                case "claude-code": state.systemSkill.claudeCodeEnabled = enabled
                default: break
                }
            }
            return "\(result.agent) 系统 Skill：\(Self.systemSkillStatusText(result.status))"
        }.value
    }

    private static func systemSkillStatusText(_ status: SystemSkillEntryStatus) -> String {
        switch status {
        case .installed: "已安装"
        case .alreadyCorrect: "状态正确"
        case .repaired: "已修复"
        case .conflict: "存在不受管冲突"
        case .disabled: "已停用"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
