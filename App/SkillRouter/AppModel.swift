import AppKit
import Foundation
import SkillRouterCore

struct ProjectSnapshot: Sendable {
    let manifest: ProjectManifest
    let reconciliation: ReconciliationReport
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = RouterState()
    @Published private(set) var updateChecks: [UpdateCheckResult] = []
    @Published private(set) var bootstrapResult: SystemSkillInstallResult?
    @Published var isBusy = false
    @Published var notice: String?
    @Published var errorMessage: String?

    let paths: RouterPaths
    let homeDirectory: URL
    private let environment: [String: String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) {
        self.environment = environment
        let resolvedHome = homeDirectory
            ?? environment["SKILL_ROUTER_USER_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        self.homeDirectory = resolvedHome
        self.paths = RouterPaths.production(environment: environment, homeDirectory: resolvedHome)
    }

    func bootstrap(appExecutable: URL? = Bundle.main.executableURL) async {
        await run("初始化完成") { [environment, homeDirectory] in
            let result = try BootstrapService().bootstrap(
                environment: environment,
                homeDirectory: homeDirectory,
                appExecutable: appExecutable
            )
            return result
        } assign: { result in
            self.bootstrapResult = result
        }
        await reconcileRegisteredProjects()
        await refresh(showProgress: false)
    }

    func refresh(showProgress: Bool = true) async {
        let paths = paths
        if showProgress { isBusy = true }
        defer { if showProgress { isBusy = false } }
        do {
            state = try await Task.detached {
                let store = RouterStateStore(paths: paths)
                _ = try ProjectService(store: store).registeredProjects()
                return try store.load()
            }.value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discoverLocal(_ source: URL) async throws -> [SkillCandidate] {
        try await Task.detached {
            try SkillDiscovery().discover(in: source)
        }.value
    }

    func importLocal(
        source: URL,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async -> Bool {
        let paths = paths
        return await runBool {
            let suite = try suiteName.map(SuiteName.init(rawValue:))
            return try LocalImportService(store: RouterStateStore(paths: paths)).importSkills(
                from: source,
                selectedNames: selected,
                suiteName: suite,
                conflictResolutions: conflicts
            )
        } message: { result in
            "已导入 \(result.imported.count) 个 Skill"
        }
    }

    func prepareGit(_ remoteURL: String) async throws -> PreparedGitImport {
        let paths = paths
        return try await Task.detached {
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
    ) async throws {
        let paths = paths
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let result = try await Task.detached {
            let suite = try suiteName.map(SuiteName.init(rawValue:))
            return try GitImportService(store: RouterStateStore(paths: paths)).commit(
                prepared,
                selectedNames: selected,
                suiteName: suite,
                conflictResolutions: conflicts
            )
        }.value
        showTransientNotice("已从 Git 导入 \(result.imported.count) 个 Skill")
        await refresh(showProgress: false)
    }

    func deleteSkill(_ name: SkillName) async {
        let paths = paths
        _ = await runBool {
            try CentralLibraryService(store: RouterStateStore(paths: paths)).delete(skillNames: [name])
        } message: { result in
            if result.projectFailures.isEmpty {
                return "已删除 \(result.deleted.count) 个 Skill"
            }
            return "中央 Skill 已删除，\(result.projectFailures.count) 个项目需要手动协调"
        }
    }

    func renameSuite(from oldName: SuiteName, to newNameText: String) async -> Bool {
        let paths = paths
        return await runBool {
            let newName = try SuiteName(rawValue: newNameText)
            return try CentralLibraryService(store: RouterStateStore(paths: paths))
                .renameSuite(from: oldName, to: newName)
        } message: { result in
            "已将套件 \(result.oldName.rawValue) 重命名为 \(result.newName.rawValue)"
        }
    }

    func registerProject(
        _ project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async -> Bool {
        let paths = paths
        return await runBool {
            let service = ProjectService(store: RouterStateStore(paths: paths))
            if targets.isEmpty {
                _ = try service.register(project: project)
            } else {
                for (id, target) in targets {
                    _ = try service.register(project: project, targetID: id, target: target)
                }
            }
            return project.path
        } message: { "已注册项目：\($0)" }
    }

    func unregisterProject(_ project: URL) async {
        let paths = paths
        _ = await runBool {
            try ProjectService(store: RouterStateStore(paths: paths)).unregister(project: project)
            return project.path
        } message: { "已取消注册：\($0)；项目清单和链接保持不变" }
    }

    func install(
        names: [SkillName],
        project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async -> Bool {
        let paths = paths
        return await runBool {
            let service = ProjectService(store: RouterStateStore(paths: paths))
            var partial = false
            for (id, target) in targets {
                partial = try service.install(
                    skillNames: names,
                    project: project,
                    targetID: id,
                    target: target
                ).isPartial || partial
            }
            return partial
        } message: { partial in
            partial ? "安装请求部分完成，请查看项目冲突" : "项目 Skill 已协调"
        }
    }

    func uninstallAll(project: URL) async {
        let paths = paths
        _ = await runBool {
            try ProjectService(store: RouterStateStore(paths: paths)).uninstallAll(project: project)
        } message: { _ in "已卸载项目中的全部受管 Skill，项目和目标仍保留" }
    }

    func uninstall(name: SkillName, project: URL, targetID: String? = nil) async -> Bool {
        let paths = paths
        return await runBool {
            try ProjectService(store: RouterStateStore(paths: paths)).uninstall(
                skillNames: [name],
                project: project,
                targetID: targetID
            )
        } message: { _ in
            if let targetID { return "已从目标 \(targetID) 卸载 \(name.rawValue)" }
            return "已从项目卸载 \(name.rawValue)"
        }
    }

    func gitIgnoreEntries(project: URL) async throws -> [String] {
        let paths = paths
        return try await Task.detached {
            try ProjectService(store: RouterStateStore(paths: paths)).gitIgnoreEntries(project: project)
        }.value
    }

    func addGitIgnoreEntries(project: URL) async -> Bool {
        let paths = paths
        return await runBool {
            try ProjectService(store: RouterStateStore(paths: paths)).addGitIgnoreEntries(project: project)
        } message: { added in
            added.isEmpty ? ".gitignore 已包含全部建议" : "已向 .gitignore 添加 \(added.count) 条忽略项"
        }
    }

    func checkUpdates(force: Bool = true, showNotice: Bool = true) async {
        let paths = paths
        if showNotice { isBusy = true }
        defer { if showNotice { isBusy = false } }
        do {
            let checks = try await Task.detached {
                try GitUpdateService(store: RouterStateStore(paths: paths)).checkForUpdates(force: force)
            }.value
            updateChecks = checks
            if showNotice { showTransientNotice("更新检查完成") }
        } catch {
            if showNotice { errorMessage = error.localizedDescription }
        }
        await refresh(showProgress: false)
    }

    func applyUpdate(sourceID: UUID) async {
        let paths = paths
        _ = await runBool {
            try GitUpdateService(store: RouterStateStore(paths: paths)).applyUpdate(sourceID: sourceID)
        } message: { result in
            var message = "已更新 \(result.updated.count) 个 Skill"
            if !result.removed.isEmpty { message += "，删除 \(result.removed.count) 个上游已移除 Skill" }
            if !result.discovered.isEmpty { message += "，发现 \(result.discovered.count) 个新候选" }
            if !result.projectFailures.isEmpty { message += "；\(result.projectFailures.count) 个项目需要手动协调" }
            return message
        }
    }

    func projectSnapshot(_ project: URL) async throws -> ProjectSnapshot {
        let paths = paths
        return try await Task.detached {
            let store = RouterStateStore(paths: paths)
            let manifest = try ProjectManifestStore().load(from: project)
            let reconciliation = try ProjectService(store: store).reconcile(project: project)
            return ProjectSnapshot(manifest: manifest, reconciliation: reconciliation)
        }.value
    }

    func referencingProjects(skillName: SkillName) async -> [String] {
        let paths = paths
        return await Task.detached {
            let store = RouterStateStore(paths: paths)
            let service = ProjectService(store: store)
            guard let projects = try? service.registeredProjects() else { return [] }
            return projects.compactMap { project in
                let url = URL(fileURLWithPath: project.path, isDirectory: true)
                guard let manifest = try? ProjectManifestStore().load(from: url),
                      manifest.skills[skillName.rawValue] != nil else { return nil }
                return project.path
            }.sorted()
        }.value
    }

    func exportArtifact(names: Set<SkillName>?, destination: URL) async -> Bool {
        let paths = paths
        return await runBool {
            try ArtifactService(store: RouterStateStore(paths: paths)).export(skillNames: names, to: destination)
        } message: { "已导出 \($0.skillNames.count) 个 Skill：\($0.destination.path)" }
    }

    func inspectArtifact(_ archive: URL) async throws -> ArtifactManifest {
        let paths = paths
        return try await Task.detached {
            try ArtifactService(store: RouterStateStore(paths: paths)).inspect(archive)
        }.value
    }

    func importArtifact(
        _ archive: URL,
        skillConflicts: [SkillName: SkillConflictResolution],
        suiteRenames: [SuiteName: SuiteName],
        skippedSuites: Set<SuiteName>
    ) async -> Bool {
        let paths = paths
        return await runBool {
            try ArtifactService(store: RouterStateStore(paths: paths)).importArtifact(
                from: archive,
                options: ArtifactImportOptions(
                    skillConflicts: skillConflicts,
                    suiteRenames: suiteRenames,
                    skippedSuites: skippedSuites
                )
            )
        } message: { "已从制品导入 \($0.imported.count) 个 Skill" }
    }

    func repairSystemSkill() async {
        await bootstrap()
    }

    func setSystemSkill(enabled: Bool, agent: String) async {
        let paths = paths
        let home = homeDirectory
        _ = await runBool {
            let result = try SystemSkillInstaller(paths: paths, homeDirectory: home)
                .setEnabled(enabled, agent: agent)
            try RouterStateStore(paths: paths).withExclusiveState { state in
                switch agent {
                case "codex": state.systemSkill.codexEnabled = enabled
                case "claude-code": state.systemSkill.claudeCodeEnabled = enabled
                default: break
                }
            }
            return result
        } message: { result in
            "\(result.agent) 系统 Skill：\(Self.systemSkillStatusText(result.status))"
        }
    }

    func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func run<T: Sendable>(
        _ successMessage: String,
        operation: @escaping @Sendable () throws -> T,
        assign: @escaping (T) -> Void
    ) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let value = try await Task.detached(operation: operation).value
            assign(value)
            showTransientNotice(successMessage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runBool<T: Sendable>(
        operation: @escaping @Sendable () throws -> T,
        message: @escaping (T) -> String
    ) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let value = try await Task.detached(operation: operation).value
            showTransientNotice(message(value))
            await refresh(showProgress: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func showTransientNotice(_ message: String) {
        notice = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if notice == message { notice = nil }
        }
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

    private func reconcileRegisteredProjects() async {
        let paths = paths
        await Task.detached {
            let store = RouterStateStore(paths: paths)
            let service = ProjectService(store: store)
            guard let projects = try? service.registeredProjects() else { return }
            for project in projects {
                _ = try? service.reconcile(project: URL(fileURLWithPath: project.path, isDirectory: true))
            }
        }.value
    }
}
