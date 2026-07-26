import AppKit
import SwiftUI

@MainActor
private final class SkillRouterAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
