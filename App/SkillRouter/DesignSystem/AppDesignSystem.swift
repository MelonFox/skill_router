import SwiftUI

enum AppTheme {
    static let sidebarWidth: CGFloat = 208
    static let sidebarTopInset: CGFloat = 45
    static let pageTopInset: CGFloat = 44
    static let rowHeight: CGFloat = 66
    static let windowRadius: CGFloat = 12
    static let panelRadius: CGFloat = 10
    static let controlRadius: CGFloat = 8

    static func stage(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.06 : 0.82) }
    static func sidebar(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.22 : 0.94) }
    static func workspace(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.075 : 0.985) }
    static func surface(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.17 : 0.995) }
    static func mutedSurface(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.19 : 0.96) }
    static func hover(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.235 : 0.945) }
    static func selected(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.265 : 0.91) }
    static func border(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.255 : 0.88) }
    static func strongBorder(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.35 : 0.80) }
    static func primary(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.93 : 0.20) }
    static func primaryInk(_ scheme: ColorScheme) -> Color { gray(scheme == .dark ? 0.16 : 0.98) }
    static func positive(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.38, green: 0.78, blue: 0.51) : Color(red: 0.16, green: 0.58, blue: 0.32)
    }
    static func warning(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.90, green: 0.66, blue: 0.25) : Color(red: 0.72, green: 0.45, blue: 0.08)
    }
    static func warningSurface(_ scheme: ColorScheme) -> Color {
        warning(scheme).opacity(scheme == .dark ? 0.16 : 0.10)
    }
    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.92, green: 0.43, blue: 0.39) : Color(red: 0.72, green: 0.20, blue: 0.17)
    }

    private static func gray(_ white: Double) -> Color {
        Color(.sRGB, white: white, opacity: 1)
    }
}

enum AppTypography {
    static let pageTitle: CGFloat = 28
    static let emphasis: CGFloat = 14
    static let body: CGFloat = 13
    static let secondary: CGFloat = 12
    static let caption: CGFloat = 11
    static let micro: CGFloat = 10
}

struct AppPageHeader<Actions: View>: View {
    let title: String
    let description: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: AppTypography.pageTitle, weight: .bold))
                .tracking(-0.8)
            HStack(alignment: .center, spacing: 20) {
                Text(description)
                    .font(.system(size: AppTypography.body))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) { actions() }
            }
            .frame(minHeight: 28)
        }
        .padding(.horizontal, 3)
    }
}

struct AppIconAction: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppIconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: AppTypography.body))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(AppControlBackground())
    }
}

struct AppSegmentedPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button(option.1) { selection = option.0 }
                    .buttonStyle(.plain)
                    .font(.system(size: AppTypography.secondary, weight: selection == option.0 ? .semibold : .regular))
                    .foregroundStyle(selection == option.0 ? Color.primary : Color.secondary)
                    .frame(minWidth: 42, minHeight: 27)
                    .padding(.horizontal, 4)
                    .background {
                        if selection == option.0 {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(AppTheme.surface(colorScheme))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(AppTheme.border(colorScheme), lineWidth: 1)
                                }
                        }
                    }
            }
        }
        .padding(2)
        .background(AppControlBackground())
    }
}

struct AppSectionHeader: View {
    let title: String
    let count: Int?
    let trailing: String?

    init(_ title: String, count: Int? = nil, trailing: String? = nil) {
        self.title = title
        self.count = count
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: AppTypography.body, weight: .semibold))
            if let count { Text("\(count) 项").font(.system(size: AppTypography.secondary)).foregroundStyle(.tertiary) }
            Spacer()
            if let trailing { Text(trailing).font(.system(size: AppTypography.secondary)).foregroundStyle(.tertiary) }
        }
        .frame(minHeight: 30)
        .padding(.horizontal, 3)
    }
}

struct AppPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(AppTheme.surface(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.panelRadius, style: .continuous)
                    .stroke(AppTheme.border(colorScheme), lineWidth: 1)
            }
    }
}

struct AppEntityRow<Leading: View, Content: View, Trailing: View>: View {
    let action: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading()
                content().frame(maxWidth: .infinity, alignment: .leading)
                trailing()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: AppTheme.rowHeight)
            .contentShape(Rectangle())
            .background(isHovering ? AppTheme.hover(colorScheme) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct AppIconBadge: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(.quaternary, lineWidth: 1))
    }
}

enum AppStatusTone {
    case neutral
    case good
    case warning
    case danger
}

struct AppStatusPill: View {
    let text: String
    var systemImage: String? = nil
    var tone: AppStatusTone = .neutral

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.system(size: AppTypography.caption, weight: .medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, tone == .neutral || tone == .good ? 0 : 7)
        .padding(.vertical, tone == .neutral || tone == .good ? 0 : 3)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: .secondary
        case .good: AppTheme.positive(colorScheme)
        case .warning: AppTheme.warning(colorScheme)
        case .danger: AppTheme.danger(colorScheme)
        }
    }

    private var background: Color {
        switch tone {
        case .neutral, .good: .clear
        case .warning: AppTheme.warningSurface(colorScheme)
        case .danger: AppTheme.danger(colorScheme).opacity(0.10)
        }
    }
}

struct AppEmptyState: View {
    let title: String
    let description: String
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage).font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: AppTypography.emphasis, weight: .semibold))
            Text(description).font(.system(size: AppTypography.secondary)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(24)
    }
}

struct AppModalFrame<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let width: CGFloat
    let minHeight: CGFloat
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String? = nil,
        width: CGFloat = 570,
        minHeight: CGFloat = 360,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.minHeight = minHeight
        self.onClose = onClose
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 16, weight: .semibold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                AppIconAction(systemImage: "xmark", label: "关闭", action: onClose)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            Divider()
            ScrollView { content().padding(18).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            footer().padding(.horizontal, 18).padding(.vertical, 10)
        }
        .frame(width: width)
        .frame(minHeight: minHeight, maxHeight: 680)
        .background(AppTheme.surface(colorScheme))
    }
}

struct AppFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: AppTypography.secondary, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) { content() }
                .background(AppTheme.mutedSurface(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                        .stroke(AppTheme.border(colorScheme), lineWidth: 1)
                }
        }
    }
}

struct AppLabeledRow<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.system(size: AppTypography.caption))
                .foregroundStyle(.tertiary)
                .frame(width: 104, alignment: .leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 46)
    }
}

struct AppInlineNotice: View {
    let text: String
    var tone: AppStatusTone = .warning
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone == .danger ? "xmark.octagon" : "exclamationmark.triangle")
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: AppTypography.caption))
        .foregroundStyle(tone == .danger ? AppTheme.danger(colorScheme) : AppTheme.warning(colorScheme))
        .padding(11)
        .background(
            tone == .danger ? AppTheme.danger(colorScheme).opacity(0.09) : AppTheme.warningSurface(colorScheme),
            in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
        )
    }
}

struct AppActionFooter<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { HStack(spacing: 7) { Spacer(); content() } }
}

struct AppToast: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.system(size: AppTypography.body, weight: .medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.border(colorScheme), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            .accessibilityLabel(text)
    }
}

struct AppBusyOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在处理…").font(.system(size: AppTypography.body, weight: .medium))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.border(colorScheme), lineWidth: 1)
            }
        }
        .accessibilityLabel("正在处理，请稍候")
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AppTypography.body, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 31)
            .foregroundStyle(AppTheme.primaryInk(colorScheme))
            .background(AppTheme.primary(colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AppTypography.body, weight: .medium))
            .padding(.horizontal, 11)
            .frame(minHeight: 31)
            .background(configuration.isPressed ? AppTheme.hover(colorScheme) : AppTheme.surface(colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                    .stroke(AppTheme.border(colorScheme), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))
            .opacity(isEnabled ? 1 : 0.42)
    }
}

private struct AppIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.primary : Color.secondary)
            .background(configuration.isPressed ? AppTheme.hover(colorScheme) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct AppControlBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            .fill(AppTheme.mutedSurface(colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .stroke(AppTheme.border(colorScheme), lineWidth: 1)
            }
    }
}

#if DEBUG
#Preview("公共组件 · 浅色") {
    VStack(spacing: 16) {
        AppPageHeader(title: "技能", description: "统一管理本机 Skill，并按需分发到已注册项目。") {
            AppIconAction(systemImage: "plus", label: "导入技能") {}
        }
        AppSearchField(placeholder: "搜索技能…", text: .constant(""))
        AppPanel {
            AppEntityRow(action: {}) {
                AppIconBadge(systemImage: "shippingbox")
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("baoyu-design").font(.system(size: AppTypography.body, weight: .semibold))
                    Text("用于验证长文本截断与统一列表密度的示例说明。")
                        .font(.system(size: AppTypography.secondary)).foregroundStyle(.secondary).lineLimit(1)
                }
            } trailing: {
                AppStatusPill(text: "本地 Skill", tone: .neutral)
            }
        }
        AppStatusPill(text: "需要协调", systemImage: "exclamationmark.triangle", tone: .warning)
    }
    .padding(24)
    .frame(width: 700)
}

#Preview("公共组件 · 深色与空状态") {
    AppPanel {
        AppEmptyState(title: "没有匹配项", description: "调整搜索条件后重试。", systemImage: "magnifyingglass")
    }
    .padding(24)
    .frame(width: 520)
    .preferredColorScheme(.dark)
}
#endif
