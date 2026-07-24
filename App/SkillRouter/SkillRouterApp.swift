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
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Skill Router") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    SkillRouterAppActivation.bringToFront()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("刷新") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
