import SkillRouterCore
import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 0) {
            AppSidebar(selection: $app.route)
                .frame(width: AppTheme.sidebarWidth)

            ZStack {
                AppTheme.workspace(colorScheme)
                Group {
                    switch app.route {
                    case .skills: SkillsPage()
                    case .projects: ProjectsPage()
                    case .settings: SettingsPage()
                    }
                }
                .id(app.route)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.top, 4)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
        }
        .background(AppTheme.sidebar(colorScheme))
        .tint(AppTheme.primary(colorScheme))
        .overlay(alignment: .bottom) {
            if let notice = app.notice {
                AppToast(text: notice).padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay { if app.isBusy { AppBusyOverlay() } }
        .animation(.easeOut(duration: 0.18), value: app.notice)
        .sheet(item: $app.modal) { route in
            ModalHost(route: route)
                .environment(app)
                .presentationBackground(AppTheme.surface(colorScheme))
        }
        .alert("操作失败", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "未知错误")
        }
        .task {
            await app.bootstrap()
            while !Task.isCancelled {
                await app.checkUpdates(force: false, showNotice: false)
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
    }
}

private struct AppSidebar: View {
    @Binding var selection: AppRoute
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 51)
            Text("Skill Router")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.4)
                .padding(.horizontal, 20)
                .padding(.bottom, 17)

            VStack(spacing: 3) {
                ForEach(AppRoute.allCases) { route in
                    SidebarItem(route: route, isSelected: selection == route) {
                        selection = route
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
        .background(AppTheme.sidebar(colorScheme))
    }
}

private struct SidebarItem: View {
    let route: AppRoute
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: route.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                Text(route.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                isSelected ? AppTheme.selected(colorScheme) : (hovering ? AppTheme.hover(colorScheme) : .clear),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(route.rawValue)
    }
}

private struct ModalHost: View {
    @Environment(AppStore.self) private var app
    let route: ModalRoute

    var body: some View {
        switch route {
        case .skillDetail(let name):
            if let item = app.skills.item(named: name) {
                SkillDetailModal(item: item)
            } else {
                MissingModal(title: "Skill 不存在")
            }
        case .projectDetail(let project):
            ProjectDetailModal(project: project)
        case .localImport(let source):
            LocalImportModal(source: source)
        case .gitImport:
            GitImportModal()
        case .artifactImport(let archive):
            ArtifactImportModal(archive: archive)
        case .projectRegistration(let project):
            ProjectRegistrationModal(project: project)
        case .projectInstall(let project, let preselected):
            ProjectInstallModal(project: project, preselected: preselected)
        case .skillProjectPicker(let skill):
            SkillProjectPickerModal(skill: skill)
        }
    }
}

private struct MissingModal: View {
    @Environment(AppStore.self) private var app
    let title: String

    var body: some View {
        AppModalFrame(title: title, onClose: { app.modal = nil }) {
            AppEmptyState(title: title, description: "刷新中央库后重试。", systemImage: "exclamationmark.triangle")
        } footer: {
            AppActionFooter { Button("完成") { app.modal = nil }.buttonStyle(AppPrimaryButtonStyle()) }
        }
    }
}
