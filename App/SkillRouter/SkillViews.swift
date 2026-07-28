import AppKit
import SkillRouterCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillsPage: View {
    @Environment(AppStore.self) private var app
    @State private var showingImportPopover = false

    var body: some View {
        @Bindable var skills = app.skills

        ScrollView {
            VStack(spacing: 0) {
                AppPageHeader(
                    title: "技能",
                    description: "统一管理本机 Skill，并按需分发到已注册项目。"
                ) {
                    AppIconAction(systemImage: "plus", label: "导入技能") {
                        showingImportPopover.toggle()
                    }
                    .popover(isPresented: $showingImportPopover, arrowEdge: .top) {
                        SkillImportPopover(
                            importFromGitHub: { beginImport { app.modal = .gitImport } },
                            importFromLocalDirectory: { beginImport(chooseLocalDirectory) },
                            importFromArtifact: { beginImport(chooseArtifact) }
                        )
                    }
                }

                HStack(spacing: 10) {
                    AppSearchField(placeholder: "搜索技能…", text: $skills.searchText)
                        .frame(maxWidth: .infinity)
                    AppSegmentedPicker(
                        options: SkillSourceFilter.allCases.map { ($0, $0.label) },
                        selection: $skills.sourceFilter
                    )
                    .frame(minWidth: 150)
                }
                .padding(.top, 19)
                .padding(.bottom, 10)

                AppSectionHeader("技能库", count: skills.filteredItems.count)

                AppPanel {
                    if skills.filteredItems.isEmpty {
                        AppEmptyState(
                            title: skills.items.isEmpty ? "中央库为空" : "没有匹配的 Skill",
                            description: skills.items.isEmpty ? "从本地目录、GitHub 或 .skillrouter 文件导入第一个 Skill。" : "调整搜索词或来源筛选后重试。",
                            systemImage: "square.stack.3d.up.slash"
                        )
                    } else {
                        ForEach(Array(skills.filteredItems.enumerated()), id: \.element.id) { index, item in
                            AppEntityRow {
                                app.modal = .skillDetail(item.name)
                            } leading: {
                                AppIconBadge(systemImage: "shippingbox")
                            } content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name.rawValue)
                                        .font(.system(size: AppTypography.body, weight: .semibold))
                                        .lineLimit(1)
                                    Text(item.description)
                                        .font(.system(size: AppTypography.secondary))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            } trailing: {
                                Text(item.sourceLabel)
                                    .font(.system(size: AppTypography.caption))
                                    .foregroundStyle(.tertiary)
                            }
                            if index < skills.filteredItems.count - 1 { Divider().padding(.leading, 50) }
                        }
                    }
                }
            }
            .frame(maxWidth: 860)
            .padding(.horizontal, 32)
            .padding(.top, AppTheme.pageTopInset)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity)
        }
    }

    private func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择来源目录"
        if panel.runModal() == .OK, let url = panel.url { app.modal = .localImport(url) }
    }

    private func chooseArtifact() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .data]
        panel.allowsMultipleSelection = false
        panel.prompt = "选择制品"
        if panel.runModal() == .OK, let url = panel.url { app.modal = .artifactImport(url) }
    }

    private func beginImport(_ action: () -> Void) {
        showingImportPopover = false
        action()
    }
}

private struct SkillImportPopover: View {
    let importFromGitHub: () -> Void
    let importFromLocalDirectory: () -> Void
    let importFromArtifact: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            SkillImportOption(title: "从 Github 导入技能", action: importFromGitHub)
            SkillImportOption(title: "从本地目录导入技能", action: importFromLocalDirectory)
            SkillImportOption(title: "从 Skill Router 制品导入技能", action: importFromArtifact)
        }
        .padding(6)
        .frame(width: 220)
    }
}

private struct SkillImportOption: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: AppTypography.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    isHovering ? AppTheme.hover(colorScheme) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct SkillDetailModal: View {
    @Environment(AppStore.self) private var app
    let item: SkillListItem

    @State private var referencingProjects: [String] = []
    @State private var showDeleteConfirmation = false
    @State private var showSuiteRename = false
    @State private var suiteName = ""

    var body: some View {
        AppModalFrame(
            title: item.name.rawValue,
            subtitle: item.description,
            onClose: { app.modal = nil }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    AppIconBadge(systemImage: "shippingbox")
                    Text("中央库内容").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    AppStatusPill(text: "已托管", systemImage: "checkmark", tone: .good)
                }

                AppFormSection(title: "基本信息") {
                    AppLabeledRow(label: "来源") { Text(item.sourceLabel).font(.system(size: 11, weight: .medium)) }
                    Divider().padding(.leading, 14)
                    AppLabeledRow(label: "套件") {
                        Text(item.record.suiteName?.rawValue ?? "独立 Skill").font(.system(size: 11, weight: .medium))
                    }
                    Divider().padding(.leading, 14)
                    AppLabeledRow(label: "中央内容") {
                        Text(item.record.contentRelativePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Divider().padding(.leading, 14)
                    AppLabeledRow(label: "最近导入") {
                        Text(item.record.importedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, weight: .medium))
                    }
                }

                AppFormSection(title: "引用项目 · \(referencingProjects.count)") {
                    if referencingProjects.isEmpty {
                        AppLabeledRow(label: "项目") {
                            Text("当前没有已注册项目引用此 Skill").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(referencingProjects.enumerated()), id: \.element) { index, path in
                            AppLabeledRow(label: index == 0 ? "项目" : "") {
                                Text(path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            }
                            if index < referencingProjects.count - 1 { Divider().padding(.leading, 14) }
                        }
                    }
                }

                Text("Skill Router 不在应用内编辑内容。来源 Skill 的外部修改可能在下次更新时被覆盖。")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            AppActionFooter {
                Menu {
                    if item.record.suiteName != nil {
                        Button("重命名整个套件…", systemImage: "pencil") {
                            suiteName = item.record.suiteName?.rawValue ?? ""
                            showSuiteRename = true
                        }
                    }
                    Button("删除中央 Skill", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("更多操作")

                Button("Finder", systemImage: "folder", action: showInFinder)
                    .buttonStyle(AppSecondaryButtonStyle())
                Button("导出", systemImage: "shippingbox.and.arrow.forward", action: exportSkill)
                    .buttonStyle(AppSecondaryButtonStyle())
                Button("安装到项目", systemImage: "plus") {
                    if app.projects.items.isEmpty {
                        app.errorMessage = "请先在“项目”页面加入项目。"
                    } else {
                        app.modal = .skillProjectPicker(item.name)
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle())
            }
        }
        .task(id: item.name) {
            referencingProjects = await app.referencingProjects(skillName: item.name)
        }
        .confirmationDialog("删除中央 Skill？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    await app.deleteSkill(item.name)
                    app.modal = nil
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除会立即影响所有引用项目；应用不提供版本回滚。")
        }
        .alert("重命名套件", isPresented: $showSuiteRename) {
            TextField("新套件名称", text: $suiteName)
            Button("取消", role: .cancel) {}
            Button("重命名") {
                guard let currentSuite = item.record.suiteName else { return }
                Task {
                    if await app.renameSuite(from: currentSuite, to: suiteName) { app.modal = nil }
                }
            }
        } message: {
            Text("套件中的全部 Skill 会一起移动；项目链接保持有效。")
        }
    }

    private func showInFinder() {
        app.openInFinder(app.paths.root.appendingPathComponent(item.record.contentRelativePath))
    }

    private func exportSkill() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(item.name.rawValue).skillrouter"
        if panel.runModal() == .OK, let url = panel.url {
            Task { _ = await app.exportArtifact(names: [item.name], destination: url) }
        }
    }
}

struct SkillProjectPickerModal: View {
    @Environment(AppStore.self) private var app
    let skill: SkillName

    var body: some View {
        AppModalFrame(
            title: "安装到项目",
            subtitle: "选择要安装 \(skill.rawValue) 的项目。",
            width: 500,
            minHeight: 320,
            onClose: { app.modal = nil }
        ) {
            AppPanel {
                ForEach(Array(app.projects.items.enumerated()), id: \.element.id) { index, project in
                    AppEntityRow {
                        app.modal = .projectInstall(project.url, preselected: skill)
                    } leading: {
                        AppIconBadge(systemImage: "rectangle.stack")
                    } content: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name).font(.system(size: 12, weight: .semibold))
                            Text(project.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } trailing: {
                        Text("\(project.skillCount) 个 Skill").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    if index < app.projects.items.count - 1 { Divider().padding(.leading, 50) }
                }
            }
        } footer: {
            AppActionFooter { Button("取消") { app.modal = nil }.buttonStyle(AppSecondaryButtonStyle()) }
        }
    }
}

struct LocalImportModal: View {
    @Environment(AppStore.self) private var app
    let source: URL

    @State private var candidates: [SkillCandidate] = []
    @State private var selected = Set<SkillName>()
    @State private var suiteName = ""
    @State private var conflicts: [SkillName: SkillConflictResolution] = [:]
    @State private var loading = true
    @State private var localError: String?

    var body: some View {
        AppModalFrame(
            title: "导入本地 Skill",
            subtitle: source.path,
            width: 620,
            minHeight: 460,
            onClose: { app.modal = nil }
        ) {
            VStack(alignment: .leading, spacing: 15) {
                if loading {
                    ProgressView("正在发现候选 Skill…").frame(maxWidth: .infinity, minHeight: 230)
                } else if let localError {
                    AppEmptyState(title: "无法读取来源", description: localError, systemImage: "exclamationmark.triangle")
                } else {
                    if candidates.count > 1 {
                        TextField("套件名称", text: $suiteName).textFieldStyle(.roundedBorder)
                    }
                    AppFormSection(title: "候选 Skill · \(candidates.count)") {
                        ForEach(Array(candidates.enumerated()), id: \.element.name) { index, candidate in
                            HStack(spacing: 12) {
                                Toggle(candidate.name.rawValue, isOn: selectionBinding(candidate.name))
                                    .toggleStyle(.checkbox)
                                Spacer()
                                if app.state.skill(named: candidate.name) != nil {
                                    Picker("同名处理", selection: conflictBinding(candidate.name)) {
                                        Text("跳过").tag(SkillConflictResolution.skip)
                                        Text("替换").tag(SkillConflictResolution.replace)
                                    }
                                    .frame(width: 145)
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 45)
                            if index < candidates.count - 1 { Divider().padding(.leading, 12) }
                        }
                    }
                }
            }
        } footer: {
            AppActionFooter {
                Button("取消") { app.modal = nil }.buttonStyle(AppSecondaryButtonStyle())
                Button("导入") {
                    Task {
                        if await app.importLocal(
                            source: source,
                            selected: selected,
                            suiteName: candidates.count > 1 ? suiteName : nil,
                            conflicts: conflicts
                        ) { app.modal = nil }
                    }
                }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(loading || selected.isEmpty || (candidates.count > 1 && suiteName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .task {
            do {
                candidates = try await app.discoverLocal(source)
                selected = Set(candidates.map(\.name))
                for candidate in candidates where app.state.skill(named: candidate.name) != nil {
                    conflicts[candidate.name] = .skip
                }
            } catch {
                localError = error.localizedDescription
            }
            loading = false
        }
    }

    private func selectionBinding(_ name: SkillName) -> Binding<Bool> {
        Binding(
            get: { selected.contains(name) },
            set: { value in
                if value { selected.insert(name) } else { selected.remove(name) }
            }
        )
    }

    private func conflictBinding(_ name: SkillName) -> Binding<SkillConflictResolution> {
        Binding(get: { conflicts[name] ?? .skip }, set: { conflicts[name] = $0 })
    }
}

struct GitImportModal: View {
    @Environment(AppStore.self) private var app
    @State private var remoteURL = ""
    @State private var prepared: PreparedGitImport?
    @State private var selected = Set<SkillName>()
    @State private var suiteName = ""
    @State private var conflicts: [SkillName: SkillConflictResolution] = [:]
    @State private var loading = false
    @State private var committing = false
    @State private var localError: String?

    var body: some View {
        AppModalFrame(
            title: "从 GitHub 导入",
            subtitle: "首版只获取公开仓库默认分支，不保存凭据。",
            width: 650,
            minHeight: 480,
            onClose: cancel
        ) {
            VStack(alignment: .leading, spacing: 15) {
                TextField("公开 Git URL", text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(prepared != nil || loading || committing)

                AppInlineNotice(text: "输入 URL 即表示授权 Skill Router 读取该公开来源。")

                if let prepared {
                    if prepared.candidates.count > 1 {
                        TextField("套件名称", text: $suiteName).textFieldStyle(.roundedBorder)
                    }
                    AppFormSection(title: "候选 Skill · \(prepared.candidates.count)") {
                        ForEach(Array(prepared.candidates.enumerated()), id: \.element.name) { index, candidate in
                            HStack(spacing: 12) {
                                Toggle(candidate.name.rawValue, isOn: selectionBinding(candidate.name)).toggleStyle(.checkbox)
                                Spacer()
                                if app.state.skill(named: candidate.name) != nil {
                                    Picker("同名处理", selection: conflictBinding(candidate.name)) {
                                        Text("跳过").tag(SkillConflictResolution.skip)
                                        Text("替换").tag(SkillConflictResolution.replace)
                                    }.frame(width: 145)
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 45)
                            if index < prepared.candidates.count - 1 { Divider().padding(.leading, 12) }
                        }
                    }
                } else if loading {
                    ProgressView("正在读取仓库并发现候选…").frame(maxWidth: .infinity, minHeight: 180)
                }

                if committing { ProgressView("正在导入所选 Skill…") }
                if let localError { AppInlineNotice(text: localError, tone: .danger) }
            }
        } footer: {
            AppActionFooter {
                Button("取消", action: cancel).buttonStyle(AppSecondaryButtonStyle()).disabled(loading || committing)
                if let prepared {
                    Button(committing ? "正在导入…" : "导入") { Task { await commit(prepared) } }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(committing || selected.isEmpty || (prepared.candidates.count > 1 && suiteName.trimmingCharacters(in: .whitespaces).isEmpty))
                } else {
                    Button(localError == nil ? "读取候选" : "重新读取") { Task { await prepare() } }
                        .buttonStyle(AppPrimaryButtonStyle())
                        .disabled(remoteURL.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
            }
        }
    }

    private func prepare() async {
        loading = true
        localError = nil
        defer { loading = false }
        do {
            let value = try await app.prepareGit(remoteURL)
            prepared = value
            selected = Set(value.candidates.map(\.name))
            suiteName = value.defaultSuiteName
            for candidate in value.candidates where app.state.skill(named: candidate.name) != nil {
                conflicts[candidate.name] = .skip
            }
        } catch {
            localError = error.localizedDescription
        }
    }

    private func commit(_ prepared: PreparedGitImport) async {
        committing = true
        localError = nil
        defer { committing = false }
        do {
            try await app.commitGit(
                prepared,
                selected: selected,
                suiteName: prepared.candidates.count > 1 ? suiteName : nil,
                conflicts: conflicts
            )
            app.modal = nil
        } catch {
            localError = error.localizedDescription
            self.prepared = nil
            selected = []
            conflicts = [:]
        }
    }

    private func cancel() {
        if let prepared { app.cancelGit(prepared) }
        app.modal = nil
    }

    private func selectionBinding(_ name: SkillName) -> Binding<Bool> {
        Binding(
            get: { selected.contains(name) },
            set: { value in
                if value { selected.insert(name) } else { selected.remove(name) }
            }
        )
    }

    private func conflictBinding(_ name: SkillName) -> Binding<SkillConflictResolution> {
        Binding(get: { conflicts[name] ?? .skip }, set: { conflicts[name] = $0 })
    }
}

struct ArtifactImportModal: View {
    @Environment(AppStore.self) private var app
    let archive: URL

    @State private var manifest: ArtifactManifest?
    @State private var conflicts: [SkillName: SkillConflictResolution] = [:]
    @State private var suiteRenameText: [SuiteName: String] = [:]
    @State private var skippedSuites = Set<SuiteName>()
    @State private var localError: String?

    var body: some View {
        AppModalFrame(
            title: "导入 .skillrouter 文件",
            subtitle: archive.path,
            width: 650,
            minHeight: 480,
            onClose: { app.modal = nil }
        ) {
            VStack(alignment: .leading, spacing: 15) {
                if let manifest {
                    AppFormSection(title: "Skill · \(manifest.skills.count)") {
                        ForEach(Array(manifest.skills.enumerated()), id: \.element.name) { index, skill in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(skill.name.rawValue).font(.system(size: 12, weight: .medium))
                                    Text(skill.suiteName?.rawValue ?? "独立 Skill").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if app.state.skill(named: skill.name) != nil {
                                    Picker("同名处理", selection: Binding(
                                        get: { conflicts[skill.name] ?? .skip },
                                        set: { conflicts[skill.name] = $0 }
                                    )) {
                                        Text("跳过").tag(SkillConflictResolution.skip)
                                        Text("替换").tag(SkillConflictResolution.replace)
                                    }.frame(width: 145)
                                }
                            }
                            .padding(.horizontal, 12).frame(minHeight: 48)
                            if index < manifest.skills.count - 1 { Divider().padding(.leading, 12) }
                        }
                    }

                    ForEach(manifest.suites, id: \.name) { suite in
                        if app.state.suites.contains(where: { $0.name == suite.name && $0.sourceID != suite.sourceID }) {
                            TextField("套件 \(suite.name.rawValue) 的新名称，留空则跳过", text: Binding(
                                get: { suiteRenameText[suite.name] ?? "" },
                                set: { suiteRenameText[suite.name] = $0 }
                            )).textFieldStyle(.roundedBorder)
                        }
                    }
                } else if let localError {
                    AppEmptyState(title: "制品无效", description: localError, systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView("正在校验制品…").frame(maxWidth: .infinity, minHeight: 230)
                }
            }
        } footer: {
            AppActionFooter {
                Button("取消") { app.modal = nil }.buttonStyle(AppSecondaryButtonStyle())
                Button("导入") { Task { await importNow() } }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(manifest == nil)
            }
        }
        .task {
            do {
                let value = try await app.inspectArtifact(archive)
                manifest = value
                for skill in value.skills where app.state.skill(named: skill.name) != nil { conflicts[skill.name] = .skip }
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func importNow() async {
        guard let manifest else { return }
        var renames: [SuiteName: SuiteName] = [:]
        var skipped = skippedSuites
        for suite in manifest.suites where app.state.suites.contains(where: { $0.name == suite.name && $0.sourceID != suite.sourceID }) {
            let text = suiteRenameText[suite.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if let mapped = try? SuiteName(rawValue: text), !text.isEmpty { renames[suite.name] = mapped } else { skipped.insert(suite.name) }
        }
        if await app.importArtifact(archive, skillConflicts: conflicts, suiteRenames: renames, skippedSuites: skipped) {
            app.modal = nil
        }
    }
}
