import Foundation
import SkillRouterCore
import Testing
@testable import SkillRouterApp

@Suite("SwiftUI 应用状态与统一页面模型")
@MainActor
struct AppStoreTests {
    @Test
    func skillSearchAndSourceFilterShareOneModel() throws {
        let local = makeSkill("baoyu-design", origin: .local, description: "创建高质量界面")
        let git = makeSkill("openai-docs", origin: .git, description: "查询 API 文档")
        let store = SkillsStore()
        store.apply([local, git])

        store.searchText = "api"
        #expect(store.filteredItems.map(\.name.rawValue) == ["openai-docs"])

        store.searchText = ""
        store.sourceFilter = .local
        #expect(store.filteredItems.map(\.name.rawValue) == ["baoyu-design"])
    }

    @Test
    func projectSearchAndConflictCountAreDerived() {
        let store = ProjectsStore()
        store.apply([
            ProjectListItem(path: "/tmp/skill-router", skillCount: 3, targetCount: 1, conflictCount: 2, diagnostic: nil),
            ProjectListItem(path: "/tmp/nano-trader", skillCount: 1, targetCount: 2, conflictCount: 0, diagnostic: nil)
        ])

        #expect(store.conflictCount == 2)
        store.searchText = "nano"
        #expect(store.filteredItems.map(\.name) == ["nano-trader"])
    }

    @Test
    func appearancePersistsAcrossSettingsStores() {
        let suite = "SkillRouterAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = SettingsStore(defaults: defaults)
        #expect(first.appearance == .system)
        first.appearance = .dark

        let second = SettingsStore(defaults: defaults)
        #expect(second.appearance == .dark)
        #expect(second.appearance.colorScheme == .dark)
    }

    @Test
    func liveDashboardParsesDescriptionsAndDerivesProjectSummary() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-router-app-dashboard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = RouterPaths(root: root.appendingPathComponent("central", isDirectory: true))
        let store = RouterStateStore(paths: paths)
        try store.initializeIfNeeded()

        let describedName = try SkillName(rawValue: "described")
        let fallbackName = try SkillName(rawValue: "fallback")
        let project = root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let describedDirectory = paths.standaloneSkill(describedName)
        try FileManager.default.createDirectory(at: describedDirectory, withIntermediateDirectories: true)
        try Data("---\nname: described\ndescription: 精确说明\n---\n".utf8)
            .write(to: describedDirectory.appendingPathComponent("SKILL.md"))

        let now = Date()
        try store.save(RouterState(
            skills: [
                ManagedSkillRecord(
                    name: describedName,
                    origin: .local,
                    suiteName: nil,
                    sourceID: nil,
                    contentRelativePath: "Library/Skills/described",
                    importedAt: now
                ),
                ManagedSkillRecord(
                    name: fallbackName,
                    origin: .local,
                    suiteName: nil,
                    sourceID: nil,
                    contentRelativePath: "Library/Skills/fallback",
                    importedAt: now
                )
            ],
            projects: [RegisteredProjectRecord(path: project.path, registeredAt: now)]
        ))

        try ProjectManifestStore().save(
            ProjectManifest(
                targets: ["codex": .codex],
                skills: ["missing": DesiredSkillAssignment(targets: ["codex"])]
            ),
            to: project
        )

        let service = LiveAppService(paths: paths, environment: [:], homeDirectory: root)
        let dashboard = try await service.loadDashboard()

        #expect(dashboard.skills.first { $0.name == describedName }?.description == "精确说明")
        #expect(dashboard.skills.first { $0.name == fallbackName }?.description == "从本地目录导入的 Skill。")
        #expect(dashboard.projects.first?.skillCount == 1)
        #expect(dashboard.projects.first?.targetCount == 1)
        #expect(dashboard.projects.first?.conflictCount == 1)
    }

    @Test
    func navigationHasOnlyThreePagesAndUpdatesStayInsideSettings() async throws {
        let updateSource = GitSourceRecord(
            id: UUID(),
            remoteURL: "https://example.com/skills.git",
            suiteName: try SuiteName(rawValue: "example"),
            selectedSkills: [try SkillName(rawValue: "example")],
            lastAppliedCommit: "old",
            availableCommit: "new"
        )
        let state = RouterState(gitSources: [updateSource])
        let fake = TestAppService(snapshot: DashboardSnapshot(state: state, skills: [], projects: []))
        let app = makeApp(service: fake)

        await app.refresh()

        #expect(AppRoute.allCases == [.skills, .projects, .settings])
        #expect(app.settings.availableUpdateCount == 1)
        app.route = .settings
        app.modal = .gitImport
        #expect(app.route == .settings)
        #expect(app.modal?.id == "git-import")
    }

    @Test
    func injectedServiceReceivesImportInstallDeleteAndUpdateActions() async throws {
        let skill = try SkillName(rawValue: "example")
        let sourceID = UUID()
        let fake = TestAppService(snapshot: DashboardSnapshot(state: RouterState(), skills: [], projects: []))
        let app = makeApp(service: fake)
        let project = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

        #expect(await app.importLocal(source: project, selected: [skill], suiteName: nil, conflicts: [:]))
        #expect(await app.install(names: [skill], project: project, targets: [("codex", .codex)]))
        await app.deleteSkill(skill)
        await app.applyUpdate(sourceID: sourceID)

        #expect(fake.imported == [skill])
        #expect(fake.installed == [skill])
        #expect(fake.deleted == [skill])
        #expect(fake.updated == [sourceID])
    }

    private func makeSkill(_ name: String, origin: ManagedSkillOrigin, description: String) -> SkillListItem {
        let skillName = try! SkillName(rawValue: name)
        return SkillListItem(
            record: ManagedSkillRecord(
                name: skillName,
                origin: origin,
                suiteName: nil,
                sourceID: origin == .git ? UUID() : nil,
                contentRelativePath: "Library/Skills/\(name)",
                importedAt: .distantPast
            ),
            description: description
        )
    }

    private func makeApp(service: TestAppService) -> AppStore {
        let root = URL(fileURLWithPath: "/tmp/skill-router-app-tests", isDirectory: true)
        return AppStore(service: service, paths: RouterPaths(root: root), homeDirectory: root)
    }
}

private final class TestAppService: SkillRouterAppServicing, @unchecked Sendable {
    var snapshot: DashboardSnapshot
    var imported: [SkillName] = []
    var installed: [SkillName] = []
    var deleted: [SkillName] = []
    var updated: [UUID] = []

    init(snapshot: DashboardSnapshot) {
        self.snapshot = snapshot
    }

    func loadDashboard() async throws -> DashboardSnapshot { snapshot }

    func importLocal(
        source: URL,
        selected: Set<SkillName>,
        suiteName: String?,
        conflicts: [SkillName: SkillConflictResolution]
    ) async throws -> String {
        imported = selected.sorted()
        return "已导入"
    }

    func install(
        names: [SkillName],
        project: URL,
        targets: [(String, DistributionTargetRecord)]
    ) async throws -> String {
        installed = names.sorted()
        return "已安装"
    }

    func deleteSkill(_ name: SkillName) async throws -> String {
        deleted.append(name)
        return "已删除"
    }

    func applyUpdate(sourceID: UUID) async throws -> String {
        updated.append(sourceID)
        return "已更新"
    }
}
