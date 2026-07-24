import AppKit
import SkillRouterCore
import SwiftUI

private enum NavigationItem: String, CaseIterable, Identifiable {
    case skills = "Skills"
    case projects = "项目"
    case updates = "更新"
    case systemSkill = "系统 Skill"
    case settings = "设置"

    var id: NavigationItem { self }
    var icon: String {
        switch self {
        case .skills: "square.stack.3d.up"
        case .projects: "folder"
        case .updates: "arrow.triangle.2.circlepath"
        case .systemSkill: "wrench.and.screwdriver"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: NavigationItem = .skills

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(NavigationItem.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                        .tag(item)
                        .badge(item == .updates ? model.state.gitSources.filter { $0.availableCommit != nil }.count : 0)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Skill Router")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch selection {
                case .skills: SkillsView()
                case .projects: ProjectsView()
                case .updates: UpdatesView()
                case .systemSkill: SystemSkillView()
                case .settings: SettingsView()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let notice = model.notice {
                    StatusBanner(text: notice, systemImage: "checkmark.circle.fill", color: .green)
                }
            }
        }
        .overlay {
            if model.isBusy {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("正在处理…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("正在处理，请稍候")
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .task {
            await model.bootstrap()
            while !Task.isCancelled {
                await model.checkUpdates(force: false, showNotice: false)
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
    }
}

private struct SkillsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedName: SkillName?
    @State private var localSource: URL?
    @State private var showGitImport = false
    @State private var artifactURL: URL?
    @State private var deleteCandidate: SkillName?

    var body: some View {
        Group {
            if model.state.skills.isEmpty {
                ContentUnavailableView(
                    "中央库为空",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("从本地目录或公开 Git URL 导入第一个 Skill。")
                )
                .navigationTitle("Skills")
            } else {
                NavigationSplitView {
                    List(model.state.skills, id: \.name, selection: $selectedName) { skill in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(skill.name.rawValue).font(.headline)
                            Text(skill.origin == .local ? "本地" : "Git 来源")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(skill.name)
                        .accessibilityElement(children: .combine)
                    }
                    .navigationTitle("Skills")
                } detail: {
                    if let selectedName,
                       let skill = model.state.skills.first(where: { $0.name == selectedName }) {
                        SkillDetailView(skill: skill, deleteCandidate: $deleteCandidate)
                    } else {
                        ContentUnavailableView("选择一个 Skill", systemImage: "cursorarrow.click")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("导入本地", systemImage: "folder.badge.plus", action: chooseLocalDirectory)
                    .help("从本地目录发现并选择 Skill")
                Button("导入 Git", systemImage: "arrow.down.circle") { showGitImport = true }
                    .help("从公开 Git URL 导入")
                Button("导入制品", systemImage: "shippingbox.and.arrow.backward", action: chooseArtifact)
                    .help("导入 .skillrouter 制品")
            }
        }
        .sheet(item: $localSource) { source in
            LocalImportSheet(source: source)
                .environmentObject(model)
        }
        .sheet(isPresented: $showGitImport) {
            GitImportSheet().environmentObject(model)
        }
        .sheet(item: $artifactURL) { archive in
            ArtifactImportSheet(archive: archive).environmentObject(model)
        }
        .confirmationDialog(
            "删除中央 Skill？",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let name = deleteCandidate { Task { await model.deleteSkill(name) } }
                deleteCandidate = nil
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("删除会立即影响所有引用项目；应用不提供版本回滚。")
        }
    }

    private func chooseLocalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择来源目录"
        if panel.runModal() == .OK { localSource = panel.url }
    }

    private func chooseArtifact() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .data]
        panel.allowsMultipleSelection = false
        panel.prompt = "选择制品"
        if panel.runModal() == .OK { artifactURL = panel.url }
    }
}

private struct SkillDetailView: View {
    @EnvironmentObject private var model: AppModel
    let skill: ManagedSkillRecord
    @Binding var deleteCandidate: SkillName?
    @State private var showSuiteRename = false
    @State private var suiteName = ""
    @State private var referencingProjects: [String] = []

    var body: some View {
        Form {
            Section("身份") {
                LabeledContent("名称", value: skill.name.rawValue)
                LabeledContent("类型", value: skill.origin == .local ? "本地 Skill" : "来源 Skill")
                LabeledContent("套件", value: skill.suiteName?.rawValue ?? "独立 Skill")
            }
            Section("中央内容") {
                LabeledContent("状态", value: "中央库已托管")
                Text(skill.contentRelativePath).font(.system(.body, design: .monospaced))
                Button("在 Finder 中显示", systemImage: "folder") {
                    model.openInFinder(model.paths.root.appendingPathComponent(skill.contentRelativePath))
                }
            }
            Section("引用项目") {
                if referencingProjects.isEmpty {
                    Text("当前没有已注册项目引用此 Skill").foregroundStyle(.secondary)
                } else {
                    ForEach(referencingProjects, id: \.self) { path in
                        Text(path).font(.caption).textSelection(.enabled)
                    }
                }
            }
            Section("导出") {
                Button("导出此 Skill…", systemImage: "shippingbox.and.arrow.forward", action: exportSkill)
            }
            if let currentSuite = skill.suiteName {
                Section("套件") {
                    Button("重命名整个套件…", systemImage: "pencil") {
                        suiteName = currentSuite.rawValue
                        showSuiteRename = true
                    }
                }
            }
            Section {
                Button("删除中央 Skill", role: .destructive) { deleteCandidate = skill.name }
            } footer: {
                Text("Skill Router 不在应用内编辑内容。来源 Skill 的外部修改可能在下次更新时被覆盖。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(skill.name.rawValue)
        .alert("重命名套件", isPresented: $showSuiteRename) {
            TextField("新套件名称", text: $suiteName)
            Button("取消", role: .cancel) {}
            Button("重命名") {
                guard let currentSuite = skill.suiteName else { return }
                Task { _ = await model.renameSuite(from: currentSuite, to: suiteName) }
            }
        } message: {
            Text("套件中的全部 Skill 会一起移动；项目链接保持有效。")
        }
        .task(id: skill.name) {
            referencingProjects = await model.referencingProjects(skillName: skill.name)
        }
    }

    private func exportSkill() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(skill.name.rawValue).skillrouter"
        if panel.runModal() == .OK, let url = panel.url {
            Task { _ = await model.exportArtifact(names: [skill.name], destination: url) }
        }
    }
}

private struct LocalImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: URL
    @State private var candidates: [SkillCandidate] = []
    @State private var selected = Set<SkillName>()
    @State private var suiteName = ""
    @State private var conflicts: [SkillName: SkillConflictResolution] = [:]
    @State private var loading = true
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入本地 Skill").font(.title2.bold())
            Text(source.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if loading {
                ProgressView("正在发现候选 Skill…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let localError {
                ContentUnavailableView("无法读取来源", systemImage: "exclamationmark.triangle", description: Text(localError))
            } else {
                if candidates.count > 1 {
                    TextField("套件名称", text: $suiteName)
                        .accessibilityHint("本地多 Skill 目录必须设置套件名称")
                }
                List(candidates, id: \.name) { candidate in
                    HStack {
                        Toggle(candidate.name.rawValue, isOn: Binding(
                            get: { selected.contains(candidate.name) },
                            set: { isSelected in
                                if isSelected { selected.insert(candidate.name) } else { selected.remove(candidate.name) }
                            }
                        ))
                        Spacer()
                        if model.state.skill(named: candidate.name) != nil {
                            Picker("同名处理", selection: Binding(
                                get: { conflicts[candidate.name] ?? .skip },
                                set: { conflicts[candidate.name] = $0 }
                            )) {
                                Text("跳过").tag(SkillConflictResolution.skip)
                                Text("替换").tag(SkillConflictResolution.replace)
                            }
                            .frame(width: 150)
                        }
                    }
                }
            }
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("导入") {
                    Task {
                        let ok = await model.importLocal(
                            source: source,
                            selected: selected,
                            suiteName: candidates.count > 1 ? suiteName : nil,
                            conflicts: conflicts
                        )
                        if ok { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading || selected.isEmpty || (candidates.count > 1 && suiteName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(24)
        .frame(minWidth: 620, minHeight: 460)
        .task {
            do {
                candidates = try await model.discoverLocal(source)
                selected = Set(candidates.map(\.name))
                for candidate in candidates where model.state.skill(named: candidate.name) != nil {
                    conflicts[candidate.name] = .skip
                }
            } catch {
                localError = error.localizedDescription
            }
            loading = false
        }
    }
}

private struct GitImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var remoteURL = ""
    @State private var prepared: PreparedGitImport?
    @State private var selected = Set<SkillName>()
    @State private var suiteName = ""
    @State private var conflicts: [SkillName: SkillConflictResolution] = [:]
    @State private var loading = false
    @State private var committing = false
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("从公开 Git 导入").font(.title2.bold())
            TextField("公开 Git URL", text: $remoteURL)
                .textFieldStyle(.roundedBorder)
                .disabled(prepared != nil || loading || committing)
            Text("首版只获取默认分支，不保存凭据。输入 URL 即表示你授权读取该来源。")
                .font(.caption).foregroundStyle(.secondary)
            if let prepared {
                if prepared.candidates.count > 1 {
                    TextField("套件名称", text: $suiteName)
                }
                List(prepared.candidates, id: \.name) { candidate in
                    HStack {
                        Toggle(candidate.name.rawValue, isOn: Binding(
                            get: { selected.contains(candidate.name) },
                            set: { isSelected in
                                if isSelected { selected.insert(candidate.name) } else { selected.remove(candidate.name) }
                            }
                        ))
                        Spacer()
                        if model.state.skill(named: candidate.name) != nil {
                            Picker("同名处理", selection: Binding(
                                get: { conflicts[candidate.name] ?? .skip },
                                set: { conflicts[candidate.name] = $0 }
                            )) {
                                Text("跳过").tag(SkillConflictResolution.skip)
                                Text("替换").tag(SkillConflictResolution.replace)
                            }.frame(width: 150)
                        }
                    }
                }
            } else if loading {
                ProgressView("正在获取仓库并发现候选…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if committing {
                ProgressView("正在下载并导入所选 Skill…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let localError { Text(localError).foregroundStyle(.red).accessibilityLabel("错误：\(localError)") }
            HStack {
                Button("取消", role: .cancel) {
                    if let prepared { model.cancelGit(prepared) }
                    dismiss()
                }
                .disabled(loading || committing)
                Spacer()
                if let prepared {
                    Button(committing ? "正在导入…" : "导入") {
                        guard !committing else { return }
                        committing = true
                        localError = nil
                        Task {
                            do {
                                try await model.commitGit(
                                    prepared,
                                    selected: selected,
                                    suiteName: prepared.candidates.count > 1 ? suiteName : nil,
                                    conflicts: conflicts
                                )
                                dismiss()
                            } catch {
                                localError = error.localizedDescription
                                self.prepared = nil
                                selected = []
                                conflicts = [:]
                            }
                            committing = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(committing || selected.isEmpty || (prepared.candidates.count > 1 && suiteName.trimmingCharacters(in: .whitespaces).isEmpty))
                } else {
                    Button(localError == nil ? "读取候选" : "重新读取候选") {
                        guard !loading else { return }
                        loading = true
                        localError = nil
                        Task { await prepare() }
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(remoteURL.trimmingCharacters(in: .whitespaces).isEmpty || loading)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 660, minHeight: 500)
    }

    private func prepare() async {
        do {
            let value = try await model.prepareGit(remoteURL)
            prepared = value
            selected = Set(value.candidates.map(\.name))
            suiteName = value.defaultSuiteName
            for candidate in value.candidates where model.state.skill(named: candidate.name) != nil {
                conflicts[candidate.name] = .skip
            }
        } catch {
            localError = error.localizedDescription
        }
        loading = false
    }
}

private struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var registrationURL: URL?
    @State private var installProject: URL?
    @State private var detailProject: URL?
    @State private var unregisterCandidate: URL?

    var body: some View {
        Group {
            if model.state.projects.isEmpty {
                ContentUnavailableView(
                    "尚未注册项目",
                    systemImage: "folder.badge.plus",
                    description: Text("加入一个本机项目，然后选择分发目标和 Skill。")
                )
            } else {
                List(model.state.projects, id: \.path) { project in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(URL(fileURLWithPath: project.path).lastPathComponent).font(.headline)
                        Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button("查看状态") { detailProject = URL(fileURLWithPath: project.path, isDirectory: true) }
                            Button("安装 Skill") { installProject = URL(fileURLWithPath: project.path, isDirectory: true) }
                            Button("卸载全部") { Task { await model.uninstallAll(project: URL(fileURLWithPath: project.path, isDirectory: true)) } }
                            Button("取消注册", role: .destructive) { unregisterCandidate = URL(fileURLWithPath: project.path, isDirectory: true) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("项目")
        .toolbar {
            Button("加入项目", systemImage: "plus", action: chooseProject)
                .help("把本机项目加入 Skill Router")
        }
        .sheet(item: $registrationURL) { url in
            ProjectRegistrationSheet(project: url).environmentObject(model)
        }
        .sheet(item: $installProject) { url in
            ProjectInstallSheet(project: url).environmentObject(model)
        }
        .sheet(item: $detailProject) { url in
            ProjectDetailSheet(project: url).environmentObject(model)
        }
        .confirmationDialog("取消注册项目？", isPresented: Binding(
            get: { unregisterCandidate != nil },
            set: { if !$0 { unregisterCandidate = nil } }
        )) {
            Button("取消注册", role: .destructive) {
                if let project = unregisterCandidate { Task { await model.unregisterProject(project) } }
                unregisterCandidate = nil
            }
            Button("返回", role: .cancel) {}
        } message: {
            Text("只移除本机注册记录，不修改项目清单和已有链接。")
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "加入项目"
        if panel.runModal() == .OK { registrationURL = panel.url }
    }
}

private struct ProjectRegistrationSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let project: URL
    @State private var codex = false
    @State private var claude = false
    @State private var customID = ""
    @State private var customPath = ""

    var body: some View {
        Form {
            Section("项目") { Text(project.path).textSelection(.enabled) }
            Section("分发目标") {
                Toggle("Codex（.agents/skills）", isOn: $codex)
                Toggle("Claude Code（.claude/skills）", isOn: $claude)
                TextField("自定义目标标识（可选）", text: $customID)
                TextField("项目相对路径（可选）", text: $customPath)
            }
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("注册") {
                    Task {
                        var targets: [(String, DistributionTargetRecord)] = []
                        if codex { targets.append(("codex", .codex)) }
                        if claude { targets.append(("claude-code", .claudeCode)) }
                        if !customID.isEmpty, !customPath.isEmpty,
                           let custom = try? DistributionTargetRecord(type: .custom, path: customPath) {
                            targets.append((customID, custom))
                        }
                        if await model.registerProject(project, targets: targets) { dismiss() }
                    }
                }.buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            codex = FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills").path)
            claude = FileManager.default.fileExists(atPath: project.appendingPathComponent(".claude/skills").path)
        }
    }
}

private struct ProjectInstallSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let project: URL
    @State private var selected = Set<SkillName>()
    @State private var targets: [String: DistributionTargetRecord] = [:]
    @State private var selectedTargets = Set<String>()
    @State private var manifest = ProjectManifest()
    @State private var loading = true
    @State private var localError: String?

    private var installedSkills: [ManagedSkillRecord] {
        guard !selectedTargets.isEmpty else { return [] }
        return model.state.skills.filter { skill in
            let assigned = Set(manifest.skills[skill.name.rawValue]?.targets ?? [])
            return selectedTargets.isSubset(of: assigned)
        }
    }

    private var installableSkills: [ManagedSkillRecord] {
        guard !selectedTargets.isEmpty else { return [] }
        return model.state.skills.filter { skill in
            let assigned = Set(manifest.skills[skill.name.rawValue]?.targets ?? [])
            return !selectedTargets.isSubset(of: assigned)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("向项目安装 Skill").font(.title2.bold())
            Text(project.path).font(.caption).foregroundStyle(.secondary)
            GroupBox("目标") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(targets.keys.sorted(), id: \.self) { id in
                        Toggle("\(id)（\(targets[id]?.path ?? "")）", isOn: Binding(
                            get: { selectedTargets.contains(id) },
                            set: { value in
                                if value { selectedTargets.insert(id) } else { selectedTargets.remove(id) }
                                selected.formIntersection(Set(installableSkills.map(\.name)))
                            }
                        ))
                    }
                    if loading { ProgressView() }
                    if let localError { Text(localError).foregroundStyle(.red) }
                }.padding(8)
            }
            if loading {
                ProgressView("正在读取项目安装状态…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if selectedTargets.isEmpty {
                ContentUnavailableView(
                    "请选择目标",
                    systemImage: "scope",
                    description: Text("选择至少一个分发目标后，将显示已安装和可安装的 Skill。")
                )
            } else {
                List {
                    Section("已安装到所选目标（\(installedSkills.count)）") {
                        if installedSkills.isEmpty {
                            Text("所选目标尚未安装任何 Skill").foregroundStyle(.secondary)
                        }
                        ForEach(installedSkills, id: \.name) { skill in
                            HStack {
                                Label(skill.name.rawValue, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Spacer()
                                Text(installedTargetSummary(for: skill.name))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("已安装：\(skill.name.rawValue)")
                        }
                    }
                    Section("可安装到所选目标（\(installableSkills.count)）") {
                        if installableSkills.isEmpty {
                            Text("中央库中的 Skill 已全部安装").foregroundStyle(.secondary)
                        }
                        ForEach(installableSkills, id: \.name) { skill in
                            Toggle(isOn: Binding(
                                get: { selected.contains(skill.name) },
                                set: { isSelected in
                                    if isSelected { selected.insert(skill.name) } else { selected.remove(skill.name) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(skill.name.rawValue)
                                    Text(installableTargetSummary(for: skill.name))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("可安装：\(skill.name.rawValue)")
                        }
                    }
                }
            }
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("安装") {
                    Task {
                        let chosen = selectedTargets.compactMap { id in targets[id].map { (id, $0) } }
                        if await model.install(names: Array(selected), project: project, targets: chosen) { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty || selectedTargets.isEmpty || loading)
            }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 480)
        .task {
            do {
                let snapshot = try await model.projectSnapshot(project)
                manifest = snapshot.manifest
                targets = snapshot.manifest.targets
                if targets.isEmpty {
                    targets = ["codex": .codex]
                }
                selectedTargets = Set(targets.keys)
            } catch {
                localError = error.localizedDescription
            }
            loading = false
        }
    }

    private func installedTargetSummary(for name: SkillName) -> String {
        let assigned = Set(manifest.skills[name.rawValue]?.targets ?? [])
        return "已安装：\(selectedTargets.intersection(assigned).sorted().joined(separator: "、"))"
    }

    private func installableTargetSummary(for name: SkillName) -> String {
        let assigned = Set(manifest.skills[name.rawValue]?.targets ?? [])
        let installed = selectedTargets.intersection(assigned).sorted()
        let missing = selectedTargets.subtracting(assigned).sorted()
        guard !installed.isEmpty else {
            return "尚未安装；将安装到：\(missing.joined(separator: "、"))"
        }
        return "已安装：\(installed.joined(separator: "、"))；尚缺：\(missing.joined(separator: "、"))"
    }
}

private struct ProjectDetailSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let project: URL
    @State private var snapshot: ProjectSnapshot?
    @State private var localError: String?
    @State private var gitIgnoreEntries: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("项目状态").font(.title2.bold())
            Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let snapshot {
                List {
                    Section("分发目标") {
                        ForEach(snapshot.manifest.targets.keys.sorted(), id: \.self) { id in
                            LabeledContent(id, value: snapshot.manifest.targets[id]?.path ?? "")
                        }
                    }
                    Section("Skill 意图") {
                        if snapshot.manifest.skills.isEmpty { Text("没有 Skill 使用意图").foregroundStyle(.secondary) }
                        ForEach(snapshot.manifest.skills.keys.sorted(), id: \.self) { name in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(name)
                                    Text(snapshot.manifest.skills[name]?.targets.joined(separator: "、") ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu("卸载") {
                                    if let skillName = try? SkillName(rawValue: name) {
                                        Button("从全部目标卸载", role: .destructive) {
                                            Task {
                                                if await model.uninstall(name: skillName, project: project) { await refresh() }
                                            }
                                        }
                                        ForEach(snapshot.manifest.skills[name]?.targets ?? [], id: \.self) { targetID in
                                            Button("仅从 \(targetID) 卸载") {
                                                Task {
                                                    if await model.uninstall(name: skillName, project: project, targetID: targetID) { await refresh() }
                                                }
                                            }
                                        }
                                    }
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                    }
                    Section(".gitignore 建议") {
                        if gitIgnoreEntries.isEmpty {
                            Text("当前没有需要忽略的受管链接").foregroundStyle(.secondary)
                        } else {
                            ForEach(gitIgnoreEntries, id: \.self) { entry in
                                Text(entry).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                            Button("一键添加到 .gitignore") {
                                Task { _ = await model.addGitIgnoreEntries(project: project) }
                            }
                        }
                    }
                    Section("协调结果") {
                        if snapshot.reconciliation.items.isEmpty { Text("没有偏差或变化").foregroundStyle(.secondary) }
                        ForEach(Array(snapshot.reconciliation.items.enumerated()), id: \.offset) { _, item in
                            Label(
                                "\(item.targetID)/\(item.skillName)：\(reconciliationStatusText(item.status))",
                                systemImage: item.status == .conflict || item.status == .missingCentralSkill
                                    ? "exclamationmark.triangle"
                                    : "checkmark.circle"
                            )
                        }
                    }
                }
            } else if let localError {
                ContentUnavailableView("无法读取项目", systemImage: "exclamationmark.triangle", description: Text(localError))
            } else {
                ProgressView("正在协调并读取项目状态…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 520)
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            snapshot = try await model.projectSnapshot(project)
            gitIgnoreEntries = try await model.gitIgnoreEntries(project: project)
            localError = nil
        } catch {
            localError = error.localizedDescription
        }
    }
}

private func reconciliationStatusText(_ status: ReconciliationStatus) -> String {
    switch status {
    case .installed: "已安装"
    case .alreadyCorrect: "链接正确"
    case .repaired: "已修复"
    case .removed: "已移除"
    case .conflict: "冲突"
    case .missingCentralSkill: "中央库缺失"
    }
}

private struct UpdatesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.state.gitSources.isEmpty {
                ContentUnavailableView("没有 Git 来源", systemImage: "arrow.triangle.2.circlepath", description: Text("本地 Skill 和本地套件不检查更新。"))
            } else {
                List(model.state.gitSources, id: \.id) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.suiteName?.rawValue ?? source.selectedSkills.first?.rawValue ?? "Git 来源").font(.headline)
                        Text(source.remoteURL).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        if source.availableCommit != nil {
                            Label("发现可用更新", systemImage: "arrow.down.circle.fill").foregroundStyle(.blue)
                            Button("确认并更新中央库") { Task { await model.applyUpdate(sourceID: source.id) } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Label("当前没有已知更新", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("更新")
        .toolbar {
            Button("检查更新", systemImage: "arrow.clockwise") { Task { await model.checkUpdates(force: true) } }
                .help("只检查并通知，不修改中央库")
        }
    }
}

private struct SystemSkillView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("项目请求 Skill") {
                Text("全局 skill-router Skill 允许当前项目自助注册，并安装中央库中已有 Skill。")
                Toggle("启用 Codex 全局入口", isOn: Binding(
                    get: { model.state.systemSkill.codexEnabled },
                    set: { value in Task { await model.setSystemSkill(enabled: value, agent: "codex") } }
                ))
                Toggle("启用 Claude Code 全局入口", isOn: Binding(
                    get: { model.state.systemSkill.claudeCodeEnabled },
                    set: { value in Task { await model.setSystemSkill(enabled: value, agent: "claude-code") } }
                ))
            }
            Section("安装位置") {
                LabeledContent("CLI", value: model.paths.binDirectory.appendingPathComponent("skill-router").path)
                LabeledContent("系统 Skill", value: model.paths.systemSkillsDirectory.appendingPathComponent("skill-router").path)
            }
            Button("修复 CLI 和全局入口", systemImage: "wrench.and.screwdriver") { Task { await model.repairSystemSkill() } }
        }
        .formStyle(.grouped)
        .navigationTitle("系统 Skill")
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var artifactURL: URL?

    var body: some View {
        Form {
            Section("中央库") {
                LabeledContent("位置", value: model.paths.root.path)
                Button("在 Finder 中打开", systemImage: "folder") { model.openInFinder(model.paths.root) }
            }
            Section("导出") {
                Text("导出制品不包含项目路径、书签、项目链接或 Git 缓存。")
                Button("导出全部 Skill…", systemImage: "shippingbox.and.arrow.forward", action: exportAll)
                    .disabled(model.state.skills.isEmpty)
            }
            Section("关于") {
                LabeledContent("版本", value: "0.1.0-dev")
                Text("首版自动测试只证明文件系统分发结构正确，不证明 Codex 或 Claude Code 已真实加载 Skill。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }

    private func exportAll() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SkillRouterExport.skillrouter"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { _ = await model.exportArtifact(names: nil, destination: url) }
        }
    }
}

private struct ArtifactImportSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let archive: URL
    @State private var manifest: ArtifactManifest?
    @State private var conflicts: [SkillName: SkillConflictResolution] = [:]
    @State private var suiteRenameText: [SuiteName: String] = [:]
    @State private var skippedSuites = Set<SuiteName>()
    @State private var localError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入 .skillrouter 制品").font(.title2.bold())
            Text(archive.path).font(.caption).foregroundStyle(.secondary)
            if let manifest {
                List(manifest.skills, id: \.name) { skill in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(skill.name.rawValue)
                            Text(skill.suiteName?.rawValue ?? "独立 Skill").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.state.skill(named: skill.name) != nil {
                            Picker("同名处理", selection: Binding(
                                get: { conflicts[skill.name] ?? .skip },
                                set: { conflicts[skill.name] = $0 }
                            )) {
                                Text("跳过").tag(SkillConflictResolution.skip)
                                Text("替换").tag(SkillConflictResolution.replace)
                            }.frame(width: 150)
                        }
                    }
                }
                ForEach(manifest.suites, id: \.name) { suite in
                    if let existing = model.state.suites.first(where: { $0.name == suite.name && $0.sourceID != suite.sourceID }) {
                        HStack {
                            Text("套件 \(existing.name.rawValue) 已被其他来源使用")
                            TextField("新套件名称，留空则跳过", text: Binding(
                                get: { suiteRenameText[suite.name] ?? "" },
                                set: { suiteRenameText[suite.name] = $0 }
                            ))
                        }
                    }
                }
            } else if let localError {
                ContentUnavailableView("制品无效", systemImage: "exclamationmark.triangle", description: Text(localError))
            } else {
                ProgressView("正在校验制品…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                Spacer()
                Button("导入") { Task { await importNow() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(manifest == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 500)
        .task {
            do {
                let value = try await model.inspectArtifact(archive)
                manifest = value
                for skill in value.skills where model.state.skill(named: skill.name) != nil {
                    conflicts[skill.name] = .skip
                }
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func importNow() async {
        guard let manifest else { return }
        var renames: [SuiteName: SuiteName] = [:]
        var skipped = skippedSuites
        for suite in manifest.suites where model.state.suites.contains(where: { $0.name == suite.name && $0.sourceID != suite.sourceID }) {
            let text = suiteRenameText[suite.name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if let mapped = try? SuiteName(rawValue: text), !text.isEmpty {
                renames[suite.name] = mapped
            } else {
                skipped.insert(suite.name)
            }
        }
        if await model.importArtifact(archive, skillConflicts: conflicts, suiteRenames: renames, skippedSuites: skipped) {
            dismiss()
        }
    }
}

private struct StatusBanner: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .foregroundStyle(color)
            .accessibilityLabel(text)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
