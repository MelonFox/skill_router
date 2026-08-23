import Darwin
import Foundation

public enum SystemSkillEntryStatus: String, Codable, Sendable {
    case installed
    case alreadyCorrect
    case repaired
    case conflict
    case disabled
}

public struct SystemSkillEntryResult: Codable, Equatable, Sendable {
    public let agent: String
    public let path: String
    public let status: SystemSkillEntryStatus
    public let detail: String?

    public init(agent: String, path: String, status: SystemSkillEntryStatus, detail: String? = nil) {
        self.agent = agent
        self.path = path
        self.status = status
        self.detail = detail
    }
}

public struct SystemSkillInstallResult: Codable, Equatable, Sendable {
    public let cliPath: String
    public let systemSkillPath: String
    public let entries: [SystemSkillEntryResult]

    public init(cliPath: String, systemSkillPath: String, entries: [SystemSkillEntryResult]) {
        self.cliPath = cliPath
        self.systemSkillPath = systemSkillPath
        self.entries = entries.sorted { $0.agent < $1.agent }
    }

    public var hasConflicts: Bool { entries.contains { $0.status == .conflict } }
}

public struct SystemSkillInstaller {
    private let paths: RouterPaths
    private let homeDirectory: URL
    private let writer: AtomicFileWriter
    private let fileManager: FileManager

    public init(
        paths: RouterPaths,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        writer: AtomicFileWriter = AtomicFileWriter(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.homeDirectory = homeDirectory
        self.writer = writer
        self.fileManager = fileManager
    }

    public func install(
        cliSource: URL,
        settings: SystemSkillSettings = SystemSkillSettings()
    ) throws -> SystemSkillInstallResult {
        try paths.createInfrastructureDirectories(fileManager: fileManager)
        let centralSkill = paths.systemSkillsDirectory.appendingPathComponent("skill-router", isDirectory: true)
        try fileManager.createDirectory(at: centralSkill, withIntermediateDirectories: true)
        guard let resource = systemSkillResourceURL() else {
            throw SkillRouterError.io("内置系统 Skill 资源缺失")
        }
        try writer.write(Data(contentsOf: resource), to: centralSkill.appendingPathComponent("SKILL.md"))

        let cliDestination = paths.binDirectory.appendingPathComponent("skill-router")
        guard fileManager.fileExists(atPath: cliSource.path) else {
            throw SkillRouterError.io("CLI 构建产物不存在：\(cliSource.path)")
        }
        try writer.write(Data(contentsOf: cliSource), to: cliDestination)
        guard chmod(cliDestination.path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) == 0 else {
            throw SkillRouterError.io("无法设置 CLI 可执行权限，errno=\(errno)")
        }

        let entries = try [
            ("codex", settings.codexEnabled),
            ("claude-code", settings.claudeCodeEnabled)
        ].map { agent, enabled in
            try setEnabled(enabled, agent: agent)
        }
        return SystemSkillInstallResult(
            cliPath: cliDestination.path,
            systemSkillPath: centralSkill.path,
            entries: entries
        )
    }

    private func systemSkillResourceURL() -> URL? {
        let resourceBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("SkillRouter_SkillRouterCore.bundle", isDirectory: true) }
            .flatMap(Bundle.init(url:))
        return resourceBundle?.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "Resources/system-skills/skill-router"
        ) ?? Bundle.module.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "Resources/system-skills/skill-router"
        )
    }

    public func setEnabled(_ enabled: Bool, agent: String) throws -> SystemSkillEntryResult {
        let directory: URL
        switch agent {
        case "codex": directory = homeDirectory.appendingPathComponent(".agents/skills", isDirectory: true)
        case "claude-code": directory = homeDirectory.appendingPathComponent(".claude/skills", isDirectory: true)
        default: throw SkillRouterError.io("未知系统 Skill 目标：\(agent)")
        }
        let centralSkill = paths.systemSkillsDirectory.appendingPathComponent("skill-router", isDirectory: true)
        if enabled {
            return try ensureEntry(agent: agent, directory: directory, centralSkill: centralSkill)
        }

        let entry = directory.appendingPathComponent("skill-router")
        guard isManagedEntry(entry, centralSkill: centralSkill) else {
            if fileManager.fileExists(atPath: entry.path) || isSymlink(entry) {
                return SystemSkillEntryResult(agent: agent, path: entry.path, status: .conflict, detail: "未删除不受管项目")
            }
            return SystemSkillEntryResult(agent: agent, path: entry.path, status: .disabled)
        }
        try fileManager.removeItem(at: entry)
        return SystemSkillEntryResult(agent: agent, path: entry.path, status: .disabled)
    }

    private func ensureEntry(agent: String, directory: URL, centralSkill: URL) throws -> SystemSkillEntryResult {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = directory.appendingPathComponent("skill-router")
        if isSymlink(entry) {
            let current = try fileManager.destinationOfSymbolicLink(atPath: entry.path)
            if URL(fileURLWithPath: current).standardizedFileURL == centralSkill.standardizedFileURL {
                return SystemSkillEntryResult(agent: agent, path: entry.path, status: .alreadyCorrect)
            }
            if current.hasPrefix(paths.systemSkillsDirectory.path) {
                try fileManager.removeItem(at: entry)
                try fileManager.createSymbolicLink(atPath: entry.path, withDestinationPath: centralSkill.path)
                return SystemSkillEntryResult(agent: agent, path: entry.path, status: .repaired)
            }
            return SystemSkillEntryResult(agent: agent, path: entry.path, status: .conflict, detail: "存在不受管软链接")
        }
        if fileManager.fileExists(atPath: entry.path) {
            return SystemSkillEntryResult(agent: agent, path: entry.path, status: .conflict, detail: "存在不受管文件或目录")
        }
        try fileManager.createSymbolicLink(atPath: entry.path, withDestinationPath: centralSkill.path)
        return SystemSkillEntryResult(agent: agent, path: entry.path, status: .installed)
    }

    private func isManagedEntry(_ entry: URL, centralSkill: URL) -> Bool {
        guard isSymlink(entry),
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: entry.path) else {
            return false
        }
        return URL(fileURLWithPath: destination).standardizedFileURL == centralSkill.standardizedFileURL
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

public struct BootstrapService {
    public init() {}

    public func bootstrap(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        appExecutable: URL? = Bundle.main.executableURL
    ) throws -> SystemSkillInstallResult {
        let paths = RouterPaths.production(environment: environment, homeDirectory: homeDirectory)
        let store = RouterStateStore(paths: paths)
        try store.initializeIfNeeded()
        try CentralTransactionManager(store: store).recoverPendingTransactions()

        let cliSource: URL
        if let override = environment["SKILL_ROUTER_CLI_SOURCE"], !override.isEmpty {
            cliSource = URL(fileURLWithPath: override)
        } else if let appExecutable {
            cliSource = appExecutable.deletingLastPathComponent().appendingPathComponent("skill-router")
        } else {
            throw SkillRouterError.io("无法定位 CLI 构建产物")
        }
        let settings = try store.load().systemSkill
        return try SystemSkillInstaller(paths: paths, homeDirectory: homeDirectory)
            .install(cliSource: cliSource, settings: settings)
    }
}
