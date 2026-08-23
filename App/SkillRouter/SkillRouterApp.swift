import AppKit
import SwiftUI

@MainActor
private final class SkillRouterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let resourceBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("SkillRouter_SkillRouterApp.bundle", isDirectory: true) }
            .flatMap(Bundle.init(url:))
        if let iconURL = resourceBundle?.url(forResource: "AppIcon", withExtension: "png")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        DispatchQueue.main.async {
            SkillRouterAppActivation.bringToFront()
        }
    }
}

@MainActor
enum SkillRouterAppActivation {
    static func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct SkillRouterApp: App {
    @NSApplicationDelegateAdaptor(SkillRouterAppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Skill Router") {
            RootView()
                .environment(store)
                .preferredColorScheme(store.settings.appearance.colorScheme)
                .frame(minWidth: 920, minHeight: 640)
                .onAppear {
                    SkillRouterAppActivation.bringToFront()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_040, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("技能") { store.route = .skills }
                    .keyboardShortcut("1", modifiers: .command)
                Button("项目") { store.route = .projects }
                    .keyboardShortcut("2", modifiers: .command)
                Button("设置") { store.route = .settings }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button("刷新") { Task { await store.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
