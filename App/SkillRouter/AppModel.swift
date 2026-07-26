import AppKit
import Foundation
import Observation
import SkillRouterCore
import SwiftUI

enum AppRoute: String, CaseIterable, Identifiable {
    case skills = "技能"
    case projects = "项目"
    case settings = "设置"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .skills: "square.stack.3d.up"
        case .projects: "rectangle.stack"
        case .settings: "gearshape"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
    var label: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum SkillSourceFilter: String, CaseIterable, Identifiable {
    case all
    case local
    case git

    var id: Self { self }
    var label: String {
        switch self {
        case .all: "全部"
        case .local: "本地"
        case .git: "Git"
        }
    }
}

enum ModalRoute: Identifiable {
    case skillDetail(SkillName)
    case projectDetail(URL)
    case localImport(URL)
    case gitImport
    case artifactImport(URL)
    case projectRegistration(URL)
    case projectInstall(URL, preselected: SkillName?)
    case skillProjectPicker(SkillName)

    var id: String {
        switch self {
        case .skillDetail(let name): "skill-\(name.rawValue)"
        case .projectDetail(let url): "project-\(url.path)"
        case .localImport(let url): "local-\(url.path)"
        case .gitImport: "git-import"
        case .artifactImport(let url): "artifact-\(url.path)"
        case .projectRegistration(let url): "register-\(url.path)"
        case .projectInstall(let url, let name): "install-\(url.path)-\(name?.rawValue ?? "all")"
        case .skillProjectPicker(let name): "project-picker-\(name.rawValue)"
        }
    }
}

@MainActor
@Observable
final class SkillsStore {
    var searchText = ""
    var sourceFilter: SkillSourceFilter = .all
    private(set) var items: [SkillListItem] = []

    var filteredItems: [SkillListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            let matchesSource = sourceFilter == .all
                || (sourceFilter == .local && item.record.origin == .local)
                || (sourceFilter == .git && item.record.origin == .git)
            guard matchesSource else { return false }
            guard !query.isEmpty else { return true }
            return [
                item.name.rawValue,
                item.description,
                item.record.suiteName?.rawValue ?? "",
                item.sourceLabel
            ].joined(separator: " ").lowercased().contains(query)
        }
    }

    func apply(_ items: [SkillListItem]) {
        self.items = items.sorted { $0.name < $1.name }
    }

    func item(named name: SkillName) -> SkillListItem? {
        items.first { $0.name == name }
    }
}

@MainActor
@Observable
final class ProjectsStore {
    var searchText = ""
    private(set) var items: [ProjectListItem] = []

    var filteredItems: [ProjectListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { "\($0.name) \($0.path)".lowercased().contains(query) }
    }

    var conflictCount: Int { items.reduce(0) { $0 + $1.conflictCount } }

    func apply(_ items: [ProjectListItem]) {
        self.items = items.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

@MainActor
@Observable
final class SettingsStore {
    static let appearanceKey = "SkillRouter.appearance"

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }
    private(set) var gitSources: [GitSourceRecord] = []
    private(set) var updateChecks: [UpdateCheckResult] = []
    private(set) var systemSkill = SystemSkillSettings()
    private(set) var bootstrapResult: SystemSkillInstallResult?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    var availableUpdateCount: Int {
        gitSources.filter { $0.availableCommit != nil }.count
    }

    func apply(state: RouterState, updateChecks: [UpdateCheckResult]? = nil) {
        gitSources = state.gitSources
        systemSkill = state.systemSkill
        if let updateChecks { self.updateChecks = updateChecks }
    }

    func setBootstrapResult(_ result: SystemSkillInstallResult) {
        bootstrapResult = result
    }
}

@MainActor
@Observable
final class AppStore {
    private(set) var state = RouterState()
    let skills: SkillsStore
    let projects: ProjectsStore
    let settings: SettingsStore
    var route: AppRoute = .skills
    var modal: ModalRoute?
    var isBusy = false
    var notice: String?
    var errorMessage: String?

    let paths: RouterPaths
    let homeDirectory: URL
    @ObservationIgnored private let service: any SkillRouterAppServicing

    convenience init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedHome = homeDirectory
            ?? environment["SKILL_ROUTER_USER_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let paths = RouterPaths.production(environment: environment, homeDirectory: resolvedHome)
        self.init(
            service: LiveAppService(paths: paths, environment: environment, homeDirectory: resolvedHome),
            paths: paths,
            homeDirectory: resolvedHome,
            defaults: defaults
        )
    }

    init(
        service: any SkillRouterAppServicing,
        paths: RouterPaths,
        homeDirectory: URL,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.paths = paths
        self.homeDirectory = homeDirectory
        self.skills = SkillsStore()
        self.projects = ProjectsStore()
        self.settings = SettingsStore(defaults: defaults)
    }

    func bootstrap(appExecutable: URL? = Bundle.main.executableURL) async {
        isBusy = true
        errorMessage = nil
        do {
            settings.setBootstrapResult(try await service.bootstrap(appExecutable: appExecutable))
        } catch {
            errorMessage = error.localizedDescription
        }
        isBusy = false
        await refresh(showProgress: false)
    }

    func refresh(showProgress: Bool = true) async {
        if showProgress { isBusy = true }
        defer { if showProgress { isBusy = false } }
        do {
            let snapshot = try await service.loadDashboard()
            state = snapshot.state
            skills.apply(snapshot.skills)
            projects.apply(snapshot.projects)
            settings.apply(state: snapshot.state)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discoverLocal(_ source: URL) async throws -> [SkillCandidate] {
        try await service.discoverLocal(source)
    }

    func importLocal(
        source: URL,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async -> Bool {
        await perform {
            try await service.importLocal(
                source: source,
                selected: selected,
                suiteName: suiteName,
                conflicts: conflicts
            )
        }
    }

    func prepareGit(_ remoteURL: String) async throws -> PreparedGitImport {
        try await service.prepareGit(remoteURL)
    }

    func cancelGit(_ prepared: PreparedGitImport) {
        service.cancelGit(prepared)
    }

    func commitGit(
        _ prepared: PreparedGitImport,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let message = try await service.commitGit(
            prepared,
            selected: selected,
            suiteName: suiteName,
            conflicts: conflicts
        )
        showTransientNotice(message)
        await refresh(showProgress: false)
    }

    func deleteSkill(_ name: SkillName) async {
        _ = await perform { try await service.deleteSkill(name) }
    }

    func renameSuite(from oldName: SuiteName, to newNameText: String) async -> Bool {
        await perform { try await service.renameSuite(from: oldName, to: newNameText) }
    }

    func registerProject(_ project: URL, targets: [(String, DistributionTargetRecord)]) async -> Bool {
        await perform { try await service.registerProject(project, targets: targets) }
    }

    func unregisterProject(_ project: URL) async {
        _ = await perform { try await service.unregisterProject(project) }
    }

    func install(
        names: [SkillName],
        project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async -> Bool {
        await perform { try await service.install(names: names, project: project, targets: targets) }
    }

    func uninstallAll(project: URL) async {
        _ = await perform { try await service.uninstallAll(project: project) }
    }

    func uninstall(name: SkillName, project: URL, targetID: String? = nil) async -> Bool {
        await perform { try await service.uninstall(name: name, project: project, targetID: targetID) }
    }

    func gitIgnoreEntries(project: URL) async throws -> [String] {
        try await service.gitIgnoreEntries(project: project)
    }

    func addGitIgnoreEntries(project: URL) async -> Bool {
        await perform { try await service.addGitIgnoreEntries(project: project) }
    }

    func checkUpdates(force: Bool = true, showNotice: Bool = true) async {
        if showNotice { isBusy = true }
        defer { if showNotice { isBusy = false } }
        do {
            let checks = try await service.checkUpdates(force: force)
            settings.apply(state: state, updateChecks: checks)
            if showNotice { showTransientNotice("更新检查完成") }
            await refresh(showProgress: false)
        } catch {
            if showNotice { errorMessage = error.localizedDescription }
        }
    }

    func applyUpdate(sourceID: UUID) async {
        _ = await perform { try await service.applyUpdate(sourceID: sourceID) }
    }

    func projectSnapshot(_ project: URL) async throws -> ProjectSnapshot {
        try await service.projectSnapshot(project)
    }

    func referencingProjects(skillName: SkillName) async -> [String] {
        await service.referencingProjects(skillName: skillName)
    }

    func exportArtifact(names: Set<SkillName>?, destination: URL) async -> Bool {
        await perform { try await service.exportArtifact(names: names, destination: destination) }
    }

    func inspectArtifact(_ archive: URL) async throws -> ArtifactManifest {
        try await service.inspectArtifact(archive)
    }

    func importArtifact(
        _ archive: URL,
        skillConflicts: [SkillName: SkillConflictResolution],
        suiteRenames: [SuiteName: SuiteName],
        skippedSuites: Set<SuiteName>
    ) async -> Bool {
        await perform {
            try await service.importArtifact(
                archive,
                skillConflicts: skillConflicts,
                suiteRenames: suiteRenames,
                skippedSuites: skippedSuites
            )
        }
    }

    func repairSystemSkill() async {
        await bootstrap()
        if errorMessage == nil { showTransientNotice("CLI 和系统 Skill 已检查") }
    }

    func setSystemSkill(enabled: Bool, agent: String) async {
        _ = await perform { try await service.setSystemSkill(enabled: enabled, agent: agent) }
    }

    func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func showNotice(_ text: String) {
        showTransientNotice(text)
    }

    private func perform(_ operation: () async throws -> String) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            showTransientNotice(try await operation())
            await refresh(showProgress: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func showTransientNotice(_ message: String) {
        notice = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.notice == message { self?.notice = nil }
        }
    }
}
