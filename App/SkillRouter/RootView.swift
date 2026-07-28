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
        .ignoresSafeArea(.container, edges: .top)
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
            Color.clear.frame(height: AppTheme.sidebarTopInset)
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
                SidebarRouteIcon(route: route)
                Text(route.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
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

private struct SidebarRouteIcon: View {
    let route: AppRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .skills:
            SkillsSidebarIcon()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: 18, height: 18)
        case .projects:
            Image(systemName: route.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
        case .settings:
            SettingsSidebarIcon()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: 18, height: 18)
        }
    }
}

private struct SkillsSidebarIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var icon = Path()

        icon.addEllipse(in: CGRect(x: 2.5, y: 2.5, width: 9, height: 9))
        icon.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 5, height: 5))
        icon.addEllipse(in: CGRect(x: 2.5, y: 12.5, width: 9, height: 9))
        icon.addEllipse(in: CGRect(x: 4.5, y: 14.5, width: 5, height: 5))
        icon.addEllipse(in: CGRect(x: 12.5, y: 12.5, width: 9, height: 9))
        icon.addEllipse(in: CGRect(x: 14.5, y: 14.5, width: 5, height: 5))

        icon.move(to: CGPoint(x: 17.5252, y: 11.155))
        icon.addLine(to: CGPoint(x: 17.8026, y: 10.5186))
        icon.addCurve(
            to: CGPoint(x: 20.2988, y: 7.98638),
            control1: CGPoint(x: 18.297, y: 9.38398),
            control2: CGPoint(x: 19.1876, y: 8.48059)
        )
        icon.addLine(to: CGPoint(x: 21.1534, y: 7.60631))
        icon.addCurve(
            to: CGPoint(x: 21.1534, y: 6.52289),
            control1: CGPoint(x: 21.6155, y: 7.4008),
            control2: CGPoint(x: 21.6155, y: 6.7284)
        )
        icon.addLine(to: CGPoint(x: 20.3467, y: 6.16406))
        icon.addCurve(
            to: CGPoint(x: 17.8143, y: 3.54712),
            control1: CGPoint(x: 19.2068, y: 5.65713),
            control2: CGPoint(x: 18.3002, y: 4.72031)
        )
        icon.addLine(to: CGPoint(x: 17.5295, y: 2.85945))
        icon.addCurve(
            to: CGPoint(x: 16.4705, y: 2.85945),
            control1: CGPoint(x: 17.3309, y: 2.38018),
            control2: CGPoint(x: 16.669, y: 2.38018)
        )
        icon.addLine(to: CGPoint(x: 16.1856, y: 3.54712))
        icon.addCurve(
            to: CGPoint(x: 13.6534, y: 6.16406),
            control1: CGPoint(x: 15.6997, y: 4.72031),
            control2: CGPoint(x: 14.7932, y: 5.65713)
        )
        icon.addLine(to: CGPoint(x: 12.8466, y: 6.52289))
        icon.addCurve(
            to: CGPoint(x: 12.8466, y: 7.60631),
            control1: CGPoint(x: 12.3845, y: 6.7284),
            control2: CGPoint(x: 12.3845, y: 7.4008)
        )
        icon.addLine(to: CGPoint(x: 13.7011, y: 7.98638))
        icon.addCurve(
            to: CGPoint(x: 16.1974, y: 10.5186),
            control1: CGPoint(x: 14.8124, y: 8.48059),
            control2: CGPoint(x: 15.7029, y: 9.38398)
        )
        icon.addLine(to: CGPoint(x: 16.4748, y: 11.155))
        icon.addCurve(
            to: CGPoint(x: 17.5252, y: 11.155),
            control1: CGPoint(x: 16.6778, y: 11.6209),
            control2: CGPoint(x: 17.3222, y: 11.6209)
        )
        icon.closeSubpath()

        let scale = min(rect.width, rect.height) / 24
        let x = rect.minX + (rect.width - 24 * scale) / 2
        let y = rect.minY + (rect.height - 24 * scale) / 2
        return icon.applying(
            CGAffineTransform(translationX: x, y: y)
                .scaledBy(x: scale, y: scale)
        )
    }
}

private struct SettingsSidebarIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var icon = Path()

        icon.move(to: CGPoint(x: 8.68637, y: 4.00008))
        icon.addLine(to: CGPoint(x: 11.293, y: 1.39348))
        icon.addCurve(
            to: CGPoint(x: 12.7072, y: 1.39348),
            control1: CGPoint(x: 11.6835, y: 1.00295),
            control2: CGPoint(x: 12.3167, y: 1.00295)
        )
        icon.addLine(to: CGPoint(x: 15.3138, y: 4.00008))
        icon.addLine(to: CGPoint(x: 19.0001, y: 4.00008))
        icon.addCurve(
            to: CGPoint(x: 20.0001, y: 5.00008),
            control1: CGPoint(x: 19.5524, y: 4.00008),
            control2: CGPoint(x: 20.0001, y: 4.4478)
        )
        icon.addLine(to: CGPoint(x: 20.0001, y: 8.68637))
        icon.addLine(to: CGPoint(x: 22.6067, y: 11.293))
        icon.addCurve(
            to: CGPoint(x: 22.6067, y: 12.7072),
            control1: CGPoint(x: 22.9972, y: 11.6835),
            control2: CGPoint(x: 22.9972, y: 12.3167)
        )
        icon.addLine(to: CGPoint(x: 20.0001, y: 15.3138))
        icon.addLine(to: CGPoint(x: 20.0001, y: 19.0001))
        icon.addCurve(
            to: CGPoint(x: 19.0001, y: 20.0001),
            control1: CGPoint(x: 20.0001, y: 19.5524),
            control2: CGPoint(x: 19.5524, y: 20.0001)
        )
        icon.addLine(to: CGPoint(x: 15.3138, y: 20.0001))
        icon.addLine(to: CGPoint(x: 12.7072, y: 22.6067))
        icon.addCurve(
            to: CGPoint(x: 11.293, y: 22.6067),
            control1: CGPoint(x: 12.3167, y: 22.9972),
            control2: CGPoint(x: 11.6835, y: 22.9972)
        )
        icon.addLine(to: CGPoint(x: 8.68637, y: 20.0001))
        icon.addLine(to: CGPoint(x: 5.00008, y: 20.0001))
        icon.addCurve(
            to: CGPoint(x: 4.00008, y: 19.0001),
            control1: CGPoint(x: 4.4478, y: 20.0001),
            control2: CGPoint(x: 4.00008, y: 19.5524)
        )
        icon.addLine(to: CGPoint(x: 4.00008, y: 15.3138))
        icon.addLine(to: CGPoint(x: 1.39348, y: 12.7072))
        icon.addCurve(
            to: CGPoint(x: 1.39348, y: 11.293),
            control1: CGPoint(x: 1.00295, y: 12.3167),
            control2: CGPoint(x: 1.00295, y: 11.6835)
        )
        icon.addLine(to: CGPoint(x: 4.00008, y: 8.68637))
        icon.addLine(to: CGPoint(x: 4.00008, y: 5.00008))
        icon.addCurve(
            to: CGPoint(x: 5.00008, y: 4.00008),
            control1: CGPoint(x: 4.00008, y: 4.4478),
            control2: CGPoint(x: 4.4478, y: 4.00008)
        )
        icon.addLine(to: CGPoint(x: 8.68637, y: 4.00008))
        icon.closeSubpath()

        icon.move(to: CGPoint(x: 6.00008, y: 6.00008))
        icon.addLine(to: CGPoint(x: 6.00008, y: 9.5148))
        icon.addLine(to: CGPoint(x: 3.5148, y: 12.0001))
        icon.addLine(to: CGPoint(x: 6.00008, y: 14.4854))
        icon.addLine(to: CGPoint(x: 6.00008, y: 18.0001))
        icon.addLine(to: CGPoint(x: 9.5148, y: 18.0001))
        icon.addLine(to: CGPoint(x: 12.0001, y: 20.4854))
        icon.addLine(to: CGPoint(x: 14.4854, y: 18.0001))
        icon.addLine(to: CGPoint(x: 18.0001, y: 18.0001))
        icon.addLine(to: CGPoint(x: 18.0001, y: 14.4854))
        icon.addLine(to: CGPoint(x: 20.4854, y: 12.0001))
        icon.addLine(to: CGPoint(x: 18.0001, y: 9.5148))
        icon.addLine(to: CGPoint(x: 18.0001, y: 6.00008))
        icon.addLine(to: CGPoint(x: 14.4854, y: 6.00008))
        icon.addLine(to: CGPoint(x: 12.0001, y: 3.5148))
        icon.addLine(to: CGPoint(x: 9.5148, y: 6.00008))
        icon.closeSubpath()

        icon.addEllipse(in: CGRect(x: 8.00008, y: 8.00008, width: 8, height: 8))
        icon.addEllipse(in: CGRect(x: 10.0001, y: 10.0001, width: 4, height: 4))

        let scale = min(rect.width, rect.height) / 24
        let x = rect.minX + (rect.width - 24 * scale) / 2
        let y = rect.minY + (rect.height - 24 * scale) / 2
        return icon.applying(
            CGAffineTransform(translationX: x, y: y)
                .scaledBy(x: scale, y: scale)
        )
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
