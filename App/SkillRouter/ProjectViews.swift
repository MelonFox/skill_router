import AppKit
import SkillRouterCore
import SwiftUI

struct ProjectsPage: View {
    @Environment(AppStore.self) private var app

    var body: some View {
        @Bindable var projects = app.projects

        ScrollView {
            VStack(spacing: 0) {
                AppPageHeader(
                    title: "项目",
                    description: "管理已注册项目，查看 Skill 的分发与协调状态。"
                ) {
                    AppIconAction(systemImage: "folder.badge.plus", label: "加入项目", action: chooseProject)
                }

                AppSearchField(placeholder: "搜索项目…", text: $projects.searchText)
                    .padding(.top, 19)
                    .padding(.bottom, 10)

                AppSectionHeader("本机项目", count: projects.filteredItems.count)

                AppPanel {
                    if projects.filteredItems.isEmpty {
                        AppEmptyState(
                            title: projects.items.isEmpty ? "尚未加入项目" : "没有匹配的项目",
                            description: projects.items.isEmpty ? "加入一个本机项目后即可管理 Skill 分发。" : "调整搜索词后重试。",
                            systemImage: "rectangle.stack.badge.plus"
                        )
                    } else {
                        ForEach(Array(projects.filteredItems.enumerated()), id: \.element.id) { index, project in
                            AppEntityRow {
                                app.modal = .projectDetail(project.url)
                            } leading: {
                                AppIconBadge(systemImage: "rectangle.stack")
                            } content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(project.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            } trailing: {
                                if project.conflictCount > 0 {
                                    AppStatusPill(text: "\(project.conflictCount) 项冲突", tone: .warning)
                                } else {
                                    Text("\(project.skillCount) 个 Skill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if index < projects.filteredItems.count - 1 { Divider().padding(.leading, 50) }
                        }
                    }
                }
            }
            .frame(maxWidth: 860)
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 34)
            .frame(maxWidth: .infinity)
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "加入项目"
        if panel.runModal() == .OK, let url = panel.url { app.modal = .projectRegistration(url) }
    }
}

struct ProjectRegistrationModal: View {
    @Environment(AppStore.self) private var app
    let project: URL

    @State private var codex = false
    @State private var claude = false
    @State private var customID = ""
    @State private var customPath = ""

    var body: some View {
        AppModalFrame(
            title: "加入项目",
            subtitle: project.path,
            width: 560,
            minHeight: 420,
            onClose: { app.modal = nil }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                AppFormSection(title: "分发目标") {
                    Toggle("Codex（.agents/skills）", isOn: $codex)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                    Divider().padding(.leading, 12)
                    Toggle("Claude Code（.claude/skills）", isOn: $claude)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                }
                AppFormSection(title: "自定义目标（可选）") {
                    TextField("目标标识", text: $customID)
                        .textFieldStyle(.plain).padding(.horizontal, 12).frame(minHeight: 42)
                    Divider().padding(.leading, 12)
                    TextField("项目相对路径", text: $customPath)
                        .textFieldStyle(.plain).padding(.horizontal, 12).frame(minHeight: 42)
                }
            }
        } footer: {
            AppActionFooter {
                Button("取消") { app.modal = nil }.buttonStyle(AppSecondaryButtonStyle())
                Button("加入") { Task { await register() } }.buttonStyle(AppPrimaryButtonStyle())
            }
        }
        .onAppear {
            codex = FileManager.default.fileExists(atPath: project.appendingPathComponent(".agents/skills").path)
            claude = FileManager.default.fileExists(atPath: project.appendingPathComponent(".claude/skills").path)
        }
    }

    private func register() async {
        var targets: [(String, DistributionTargetRecord)] = []
        if codex { targets.append(("codex", .codex)) }
        if claude { targets.append(("claude-code", .claudeCode)) }
        if !customID.isEmpty, !customPath.isEmpty,
           let custom = try? DistributionTargetRecord(type: .custom, path: customPath) {
            targets.append((customID, custom))
        }
        if await app.registerProject(project, targets: targets) { app.modal = nil }
    }
}

struct ProjectDetailModal: View {
    @Environment(AppStore.self) private var app
    let project: URL

    @State private var snapshot: ProjectSnapshot?
    @State private var localError: String?
    @State private var gitIgnoreEntries: [String] = []
    @State private var showUnregisterConfirmation = false
    @State private var showUninstallAllConfirmation = false

    private var hasFailures: Bool { snapshot?.reconciliation.hasFailures == true }

    var body: some View {
        AppModalFrame(
            title: project.lastPathComponent,
            subtitle: project.path,
            width: 650,
            minHeight: 520,
            onClose: { app.modal = nil }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot {
                    HStack(spacing: 10) {
                        AppIconBadge(systemImage: "rectangle.stack")
                        Text("项目分发").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        AppStatusPill(
                            text: hasFailures ? "需要协调" : "链接正确",
                            systemImage: hasFailures ? "exclamationmark.triangle" : "checkmark",
                            tone: hasFailures ? .warning : .good
                        )
                    }

                    AppFormSection(title: "分发目标 · \(snapshot.manifest.targets.count)") {
                        if snapshot.manifest.targets.isEmpty {
                            AppLabeledRow(label: "目标") { Text("尚未配置分发目标").font(.system(size: 11)).foregroundStyle(.secondary) }
                        } else {
                            ForEach(Array(snapshot.manifest.targets.keys.sorted().enumerated()), id: \.element) { index, id in
                                AppLabeledRow(label: id) {
                                    Text(snapshot.manifest.targets[id]?.path ?? "")
                                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                }
                                if index < snapshot.manifest.targets.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                    }

                    AppFormSection(title: "已请求 Skill · \(snapshot.manifest.skills.count)") {
                        if snapshot.manifest.skills.isEmpty {
                            AppLabeledRow(label: "Skill") { Text("当前项目没有 Skill 使用意图").font(.system(size: 11)).foregroundStyle(.secondary) }
                        } else {
                            ForEach(Array(snapshot.manifest.skills.keys.sorted().enumerated()), id: \.element) { index, name in
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(name).font(.system(size: 11, weight: .medium))
                                        Text(snapshot.manifest.skills[name]?.targets.joined(separator: "、") ?? "")
                                            .font(.system(size: 9)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Menu {
                                        if let skillName = try? SkillName(rawValue: name) {
                                            Button("从全部目标卸载", role: .destructive) {
                                                Task { if await app.uninstall(name: skillName, project: project) { await refresh() } }
                                            }
                                            ForEach(snapshot.manifest.skills[name]?.targets ?? [], id: \.self) { targetID in
                                                Button("仅从 \(targetID) 卸载") {
                                                    Task { if await app.uninstall(name: skillName, project: project, targetID: targetID) { await refresh() } }
                                                }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").frame(width: 28, height: 28)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .help("Skill 操作")
                                }
                                .padding(.horizontal, 14).frame(minHeight: 48)
                                if index < snapshot.manifest.skills.count - 1 { Divider().padding(.leading, 14) }
                            }
                        }
                    }

                    if !gitIgnoreEntries.isEmpty {
                        AppFormSection(title: ".gitignore 建议") {
                            ForEach(Array(gitIgnoreEntries.enumerated()), id: \.element) { index, entry in
                                AppLabeledRow(label: index == 0 ? "忽略" : "") {
                                    Text(entry).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                                }
                                if index < gitIgnoreEntries.count - 1 { Divider().padding(.leading, 14) }
                            }
                            Divider().padding(.leading, 14)
                            Button("添加到 .gitignore") { Task { _ = await app.addGitIgnoreEntries(project: project) } }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 14).frame(minHeight: 42, alignment: .leading)
                        }
                    }

                    let failures = snapshot.reconciliation.items.filter { $0.status == .conflict || $0.status == .missingCentralSkill }
                    if !failures.isEmpty {
                        AppInlineNotice(text: failures.map { "\($0.targetID)/\($0.skillName)：\(reconciliationStatusText($0.status))" }.joined(separator: "；"))
                    }
                } else if let localError {
                    AppEmptyState(title: "无法读取项目", description: localError, systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView("正在协调并读取项目状态…").frame(maxWidth: .infinity, minHeight: 280)
                }
            }
        } footer: {
            AppActionFooter {
                Menu {
                    Button("卸载全部受管 Skill", systemImage: "minus.circle", role: .destructive) {
                        showUninstallAllConfirmation = true
                    }
                    Button("取消注册项目", systemImage: "trash", role: .destructive) {
                        showUnregisterConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help("更多操作")

                Button("重新协调", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .buttonStyle(AppSecondaryButtonStyle())
                Button("安装 Skill", systemImage: "plus") { app.modal = .projectInstall(project, preselected: nil) }
                    .buttonStyle(AppPrimaryButtonStyle())
            }
        }
        .task { await refresh() }
        .confirmationDialog("卸载全部受管 Skill？", isPresented: $showUninstallAllConfirmation, titleVisibility: .visible) {
            Button("卸载全部", role: .destructive) {
                Task {
                    await app.uninstallAll(project: project)
                    await refresh()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("项目和分发目标会保留，只移除全部 Skill 使用意图与受管链接。")
        }
        .confirmationDialog("取消注册项目？", isPresented: $showUnregisterConfirmation, titleVisibility: .visible) {
            Button("取消注册", role: .destructive) {
                Task {
                    await app.unregisterProject(project)
                    app.modal = nil
                }
            }
            Button("返回", role: .cancel) {}
        } message: {
            Text("只移除本机注册记录，不修改项目清单和已有链接。")
        }
    }

    private func refresh() async {
        do {
            snapshot = try await app.projectSnapshot(project)
            gitIgnoreEntries = try await app.gitIgnoreEntries(project: project)
            localError = nil
            await app.refresh(showProgress: false)
        } catch {
            localError = error.localizedDescription
        }
    }
}

struct ProjectInstallModal: View {
    @Environment(AppStore.self) private var app
    let project: URL
    let preselected: SkillName?

    @State private var selected = Set<SkillName>()
    @State private var targets: [String: DistributionTargetRecord] = [:]
    @State private var selectedTargets = Set<String>()
    @State private var manifest = ProjectManifest()
    @State private var loading = true
    @State private var localError: String?

    private var installedSkills: [SkillListItem] {
        guard !selectedTargets.isEmpty else { return [] }
        return app.skills.items.filter { skill in
            let assigned = Set(manifest.skills[skill.name.rawValue]?.targets ?? [])
            return selectedTargets.isSubset(of: assigned)
        }
    }

    private var installableSkills: [SkillListItem] {
        guard !selectedTargets.isEmpty else { return [] }
        return app.skills.items.filter { skill in
            let assigned = Set(manifest.skills[skill.name.rawValue]?.targets ?? [])
            return !selectedTargets.isSubset(of: assigned)
        }
    }

    var body: some View {
        AppModalFrame(
            title: "安装 Skill",
            subtitle: "\(project.lastPathComponent) · 先写入完整期望，再逐项协调分发。",
            width: 640,
            minHeight: 520,
            onClose: { app.modal = nil }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView("正在读取项目安装状态…").frame(maxWidth: .infinity, minHeight: 280)
                } else if let localError {
                    AppEmptyState(title: "无法读取项目", description: localError, systemImage: "exclamationmark.triangle")
                } else {
                    AppFormSection(title: "分发目标") {
                        ForEach(Array(targets.keys.sorted().enumerated()), id: \.element) { index, id in
                            Toggle("\(id)（\(targets[id]?.path ?? "")）", isOn: targetBinding(id))
                                .toggleStyle(.checkbox)
                                .padding(.horizontal, 12).frame(minHeight: 44)
                            if index < targets.count - 1 { Divider().padding(.leading, 12) }
                        }
                    }

                    if selectedTargets.isEmpty {
                        AppEmptyState(title: "请选择目标", description: "选择至少一个分发目标后，将显示已安装和可安装的 Skill。", systemImage: "scope")
                    } else {
                        AppFormSection(title: "可安装 Skill · \(installableSkills.count)") {
                            if installableSkills.isEmpty {
                                AppLabeledRow(label: "Skill") { Text("中央库中的 Skill 已全部安装").font(.system(size: 11)).foregroundStyle(.secondary) }
                            } else {
                                ForEach(Array(installableSkills.enumerated()), id: \.element.id) { index, skill in
                                    Toggle(isOn: skillBinding(skill.name)) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(skill.name.rawValue).font(.system(size: 11, weight: .medium))
                                            Text(installableTargetSummary(for: skill.name)).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    .padding(.horizontal, 12).frame(minHeight: 48)
                                    if index < installableSkills.count - 1 { Divider().padding(.leading, 12) }
                                }
                            }
                        }

                        if !installedSkills.isEmpty {
                            AppFormSection(title: "已安装到所选目标 · \(installedSkills.count)") {
                                ForEach(Array(installedSkills.enumerated()), id: \.element.id) { index, skill in
                                    HStack(spacing: 9) {
                                        Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                                        Text(skill.name.rawValue).font(.system(size: 11, weight: .medium))
                                        Spacer()
                                        Text(installedTargetSummary(for: skill.name)).font(.system(size: 9)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 12).frame(minHeight: 42)
                                    if index < installedSkills.count - 1 { Divider().padding(.leading, 12) }
                                }
                            }
                        }
                    }
                }
            }
        } footer: {
            AppActionFooter {
                Button("取消") { app.modal = nil }.buttonStyle(AppSecondaryButtonStyle())
                Button(selected.isEmpty ? "安装" : "安装 \(selected.count) 个 Skill") { Task { await install() } }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(selected.isEmpty || selectedTargets.isEmpty || loading)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let snapshot = try await app.projectSnapshot(project)
            manifest = snapshot.manifest
            targets = snapshot.manifest.targets
            if targets.isEmpty { targets = ["codex": .codex] }
            selectedTargets = Set(targets.keys)
            if let preselected, installableSkills.contains(where: { $0.name == preselected }) { selected = [preselected] }
        } catch {
            localError = error.localizedDescription
        }
        loading = false
    }

    private func install() async {
        let chosen = selectedTargets.compactMap { id in targets[id].map { (id, $0) } }
        if await app.install(names: Array(selected), project: project, targets: chosen) { app.modal = nil }
    }

    private func targetBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedTargets.contains(id) },
            set: { value in
                if value { selectedTargets.insert(id) } else { selectedTargets.remove(id) }
                selected.formIntersection(Set(installableSkills.map(\.name)))
            }
        )
    }

    private func skillBinding(_ name: SkillName) -> Binding<Bool> {
        Binding(
            get: { selected.contains(name) },
            set: { value in if value { selected.insert(name) } else { selected.remove(name) } }
        )
    }

    private func installedTargetSummary(for name: SkillName) -> String {
        let assigned = Set(manifest.skills[name.rawValue]?.targets ?? [])
        return selectedTargets.intersection(assigned).sorted().joined(separator: "、")
    }

    private func installableTargetSummary(for name: SkillName) -> String {
        let assigned = Set(manifest.skills[name.rawValue]?.targets ?? [])
        let installed = selectedTargets.intersection(assigned).sorted()
        let missing = selectedTargets.subtracting(assigned).sorted()
        return installed.isEmpty
            ? "将安装到：\(missing.joined(separator: "、"))"
            : "已安装：\(installed.joined(separator: "、"))；尚缺：\(missing.joined(separator: "、"))"
    }
}

func reconciliationStatusText(_ status: ReconciliationStatus) -> String {
    switch status {
    case .installed: "已安装"
    case .alreadyCorrect: "链接正确"
    case .repaired: "已修复"
    case .removed: "已移除"
    case .conflict: "冲突"
    case .missingCentralSkill: "中央库缺失"
    }
}
