import AppKit
import SkillRouterCore
import SwiftUI

struct SettingsPage: View {
    @Environment(AppStore.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AppPageHeader(
                    title: "设置",
                    description: "管理外观、来源更新、系统 Skill 与中央库位置。"
                ) { EmptyView() }

                SettingsSection(title: "外观") {
                    AppLabeledRow(label: "主题") {
                        AppSegmentedPicker(
                            options: AppearanceMode.allCases.map { ($0, $0.label) },
                            selection: $settings.appearance
                        )
                        .fixedSize()
                    }
                }

                SettingsSection(title: "来源更新", trailing: settings.availableUpdateCount > 0 ? "\(settings.availableUpdateCount) 项可更新" : nil) {
                    if settings.gitSources.isEmpty {
                        AppLabeledRow(label: "Git 来源") {
                            Text("当前没有 Git 来源；本地 Skill 不检查更新。")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(settings.gitSources.enumerated()), id: \.element.id) { index, source in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.suiteName?.rawValue ?? source.selectedSkills.first?.rawValue ?? "Git 来源")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(source.remoteURL)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if source.availableCommit != nil {
                                    AppStatusPill(text: "可更新", systemImage: "arrow.down.circle", tone: .warning)
                                    Button("更新") { Task { await app.applyUpdate(sourceID: source.id) } }
                                        .buttonStyle(AppSecondaryButtonStyle())
                                } else {
                                    AppStatusPill(text: "已是最新", systemImage: "checkmark", tone: .good)
                                }
                            }
                            .padding(.horizontal, 14).frame(minHeight: 56)
                            if index < settings.gitSources.count - 1 { Divider().padding(.leading, 14) }
                        }
                    }
                    Divider().padding(.leading, 14)
                    HStack {
                        Text("检查只读取来源状态，不会修改中央库。")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("检查更新", systemImage: "arrow.clockwise") {
                            Task { await app.checkUpdates(force: true) }
                        }
                        .buttonStyle(AppSecondaryButtonStyle())
                    }
                    .padding(.horizontal, 14).frame(minHeight: 50)
                }

                SettingsSection(title: "系统 Skill") {
                    Toggle("启用 Codex 全局入口", isOn: Binding(
                        get: { settings.systemSkill.codexEnabled },
                        set: { value in Task { await app.setSystemSkill(enabled: value, agent: "codex") } }
                    ))
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    Divider().padding(.leading, 14)
                    Toggle("启用 Claude Code 全局入口", isOn: Binding(
                        get: { settings.systemSkill.claudeCodeEnabled },
                        set: { value in Task { await app.setSystemSkill(enabled: value, agent: "claude-code") } }
                    ))
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    Divider().padding(.leading, 14)
                    AppLabeledRow(label: "CLI") {
                        Text(app.paths.binDirectory.appendingPathComponent("skill-router").path)
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Divider().padding(.leading, 14)
                    AppLabeledRow(label: "系统 Skill") {
                        Text(app.paths.systemSkillsDirectory.appendingPathComponent("skill-router").path)
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Divider().padding(.leading, 14)
                    HStack {
                        Text("系统 Skill 只调用稳定 CLI，不直接编辑项目文件。")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("修复入口", systemImage: "wrench.and.screwdriver") {
                            Task { await app.repairSystemSkill() }
                        }
                        .buttonStyle(AppSecondaryButtonStyle())
                    }
                    .padding(.horizontal, 14).frame(minHeight: 50)
                }

                SettingsSection(title: "中央库") {
                    AppLabeledRow(label: "位置") {
                        Text(app.paths.root.path)
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Divider().padding(.leading, 14)
                    HStack(spacing: 8) {
                        Text("制品不包含项目路径、书签、项目链接或 Git 缓存。")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Finder", systemImage: "folder") { app.openInFinder(app.paths.root) }
                            .buttonStyle(AppSecondaryButtonStyle())
                        Button("导出全部", systemImage: "shippingbox.and.arrow.forward", action: exportAll)
                            .buttonStyle(AppSecondaryButtonStyle())
                            .disabled(app.state.skills.isEmpty)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 52)
                }

                SettingsSection(title: "关于") {
                    AppLabeledRow(label: "版本") { Text("0.1.0-dev").font(.system(size: 11, weight: .medium)) }
                    Divider().padding(.leading, 14)
                    AppLabeledRow(label: "验证边界") {
                        Text("自动测试证明文件系统分发结构，不证明 Codex 或 Claude Code 已真实加载 Skill。")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
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

    private func exportAll() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SkillRouterExport.skillrouter"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            Task { _ = await app.exportArtifact(names: nil, destination: url) }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            AppSectionHeader(title, trailing: trailing)
            AppPanel { content() }
        }
    }
}
