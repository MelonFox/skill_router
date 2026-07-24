import Foundation
import SkillRouterCore

public enum CLIExitCode: Int32, Sendable {
    case success = 0
    case usage = 64
    case validation = 65
    case missingName = 66
    case internalError = 70
    case conflict = 73
    case ioFailure = 74
    case busy = 75
    case partial = 78
}

public struct CLIExecution: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String = "", standardError: String = "") {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public struct SkillRouterCLI: Sendable {
    public static let version = "0.1.0-dev"

    public init() {}

    public func run(
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL
    ) -> CLIExecution {
        let json = arguments.contains("--json")
        let filtered = arguments.filter { $0 != "--json" }
        do {
            if filtered.isEmpty || ["help", "--help", "-h"].contains(filtered[0]) {
                return success(helpText, json: json, command: "help")
            }
            if ["version", "--version"].contains(filtered[0]) {
                return success("skill-router \(Self.version)\n", json: json, command: "version")
            }
            guard filtered[0] == "project", filtered.count >= 2 else {
                throw CLIUsageError("首版只支持 project 命令")
            }

            let parsed = try ParsedArguments(Array(filtered.dropFirst(2)))
            let project = parsed.path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? currentDirectory
            let paths = RouterPaths.production(environment: environment)
            let store = RouterStateStore(paths: paths)
            try CentralTransactionManager(store: store).recoverPendingTransactions()
            let service = ProjectService(store: store)
            let subcommand = filtered[1]

            switch subcommand {
            case "register":
                let target = try targetSelection(parsed.target, environment: environment, project: project)
                let record = try service.register(project: project, targetID: target.id, target: target.record)
                return result(
                    command: "project register",
                    text: "已注册项目：\(record.path)\n目标：\(target.id)（\(target.record.path)）\n",
                    data: RegisterOutput(path: record.path, targetID: target.id, targetPath: target.record.path),
                    json: json
                )

            case "list":
                try parsed.requireNoPositionals()
                let projects = try service.registeredProjects()
                let text = projects.isEmpty
                    ? "尚未注册项目。\n"
                    : projects.map { "\($0.path)\n" }.joined()
                return result(
                    command: "project list",
                    text: text,
                    data: ProjectListOutput(projects: projects.map(\.path)),
                    json: json
                )

            case "status", "reconcile":
                try parsed.requireNoPositionals()
                let report = try service.reconcile(project: project)
                return reconciliationExecution(
                    command: "project \(subcommand)",
                    report: report,
                    json: json
                )

            case "install":
                guard !parsed.positionals.isEmpty else {
                    throw CLIUsageError("install 至少需要一个 Skill 名称")
                }
                let names = try parsed.positionals.map(SkillName.init(rawValue:))
                let target = try targetSelection(parsed.target, environment: environment, project: project)
                let install = try service.install(
                    skillNames: names,
                    project: project,
                    targetID: target.id,
                    target: target.record
                )
                return installExecution(install, json: json)

            case "uninstall":
                guard !parsed.positionals.isEmpty || parsed.all else {
                    throw CLIUsageError("uninstall 需要 Skill 名称或 --all")
                }
                let report: ReconciliationReport
                if parsed.all {
                    guard parsed.positionals.isEmpty else {
                        throw CLIUsageError("--all 不能和 Skill 名称同时使用")
                    }
                    report = try service.uninstallAll(project: project)
                } else {
                    let names = try parsed.positionals.map(SkillName.init(rawValue:))
                    report = try service.uninstall(
                        skillNames: names,
                        project: project,
                        targetID: parsed.target
                    )
                }
                return reconciliationExecution(command: "project uninstall", report: report, json: json)

            default:
                throw CLIUsageError("未知 project 命令：\(subcommand)")
            }
        } catch let error as CLIUsageError {
            return failure(.usage, message: error.message, json: json, command: "usage")
        } catch SkillRouterError.stateBusy {
            return failure(.busy, message: SkillRouterError.stateBusy.localizedDescription, json: json, command: "project")
        } catch let error as SkillRouterError {
            let exit: CLIExitCode
            switch error {
            case .invalidSkillName, .invalidSuiteName, .invalidJSON, .unsupportedSchema, .malformedSkillManifest:
                exit = .validation
            case .missingSkill:
                exit = .missingName
            case .unmanagedPathConflict:
                exit = .conflict
            case .io, .processFailed, .invalidArchivePath:
                exit = .ioFailure
            case .stateBusy:
                exit = .busy
            }
            return failure(exit, message: error.localizedDescription, json: json, command: "project")
        } catch {
            return failure(.internalError, message: "未预期内部错误：\(error.localizedDescription)", json: json, command: "project")
        }
    }

    private func targetSelection(
        _ requested: String?,
        environment: [String: String],
        project: URL
    ) throws -> (id: String, record: DistributionTargetRecord) {
        let id = requested ?? environment["SKILL_ROUTER_AGENT"] ?? "codex"
        switch id {
        case "claude-code": return (id, .claudeCode)
        case "codex": return (id, .codex)
        default:
            let manifest = try ProjectManifestStore().load(from: project)
            guard let target = manifest.targets[id] else {
                throw SkillRouterError.io("项目尚未登记自定义目标：\(id)")
            }
            return (id, target)
        }
    }

    private func installExecution(_ install: ProjectInstallResult, json: Bool) -> CLIExecution {
        let successful = install.reconciliation.items.filter {
            [.installed, .alreadyCorrect, .repaired].contains($0.status)
        }
        let conflicts = install.reconciliation.items.filter { $0.status == .conflict }
        var lines: [String] = []
        if !successful.isEmpty { lines.append("已协调：\(successful.map(\.skillName).sorted().joined(separator: "、"))") }
        if !install.missing.isEmpty { lines.append("中央库不存在：\(install.missing.joined(separator: "、"))") }
        if !conflicts.isEmpty { lines.append("目标冲突：\(conflicts.map(\.skillName).sorted().joined(separator: "、"))") }
        let code: CLIExitCode
        if install.isPartial {
            if install.accepted.isEmpty && !install.missing.isEmpty {
                code = .missingName
            } else if successful.isEmpty && !conflicts.isEmpty && install.missing.isEmpty {
                code = .conflict
            } else {
                code = .partial
            }
        } else {
            code = .success
        }
        return result(
            command: "project install",
            text: lines.joined(separator: "\n") + "\n",
            data: install,
            json: json,
            exitCode: code
        )
    }

    private func reconciliationExecution(command: String, report: ReconciliationReport, json: Bool) -> CLIExecution {
        let text: String
        if report.items.isEmpty {
            text = "项目分发状态无变化。\n"
        } else {
            text = report.items.map { item in
                "\(item.targetID)/\(item.skillName)：\(statusText(item.status))\(item.detail.map { "（\($0)）" } ?? "")"
            }.joined(separator: "\n") + "\n"
        }
        let hasSuccess = report.items.contains { ![.conflict, .missingCentralSkill].contains($0.status) }
        let code: CLIExitCode = report.hasFailures ? (hasSuccess ? .partial : .conflict) : .success
        return result(command: command, text: text, data: report, json: json, exitCode: code)
    }

    private func statusText(_ status: ReconciliationStatus) -> String {
        switch status {
        case .installed: "已安装"
        case .alreadyCorrect: "链接正确"
        case .repaired: "已修复"
        case .removed: "已移除"
        case .conflict: "冲突"
        case .missingCentralSkill: "中央库缺失"
        }
    }

    private func success(_ text: String, json: Bool, command: String) -> CLIExecution {
        result(command: command, text: text, data: EmptyOutput(), json: json)
    }

    private func result<T: Encodable>(
        command: String,
        text: String,
        data: T,
        json: Bool,
        exitCode: CLIExitCode = .success
    ) -> CLIExecution {
        if json {
            let envelope = CLIEnvelope(
                schemaVersion: 1,
                command: command,
                success: exitCode == .success,
                exitCode: exitCode.rawValue,
                data: data
            )
            return CLIExecution(exitCode: exitCode.rawValue, standardOutput: encodeJSON(envelope))
        }
        return CLIExecution(exitCode: exitCode.rawValue, standardOutput: text)
    }

    private func failure(
        _ exitCode: CLIExitCode,
        message: String,
        json: Bool,
        command: String
    ) -> CLIExecution {
        if json {
            let envelope = CLIErrorEnvelope(
                schemaVersion: 1,
                command: command,
                success: false,
                exitCode: exitCode.rawValue,
                error: message
            )
            return CLIExecution(exitCode: exitCode.rawValue, standardError: encodeJSON(envelope))
        }
        return CLIExecution(exitCode: exitCode.rawValue, standardError: "错误：\(message)\n")
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{\"schemaVersion\":1,\"success\":false}\n" }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private var helpText: String {
        """
        Skill Router 项目侧命令行工具

        用法：
          skill-router project register [--path <路径>] [--target <目标>]
          skill-router project list [--json]
          skill-router project status [--path <路径>] [--json]
          skill-router project install <skill>... [--path <路径>] [--target <目标>] [--json]
          skill-router project uninstall <skill>... [--path <路径>] [--target <目标>] [--json]
          skill-router project uninstall --all [--path <路径>] [--json]
          skill-router project reconcile [--path <路径>] [--json]

        未指定路径时使用当前工作目录。未指定目标时使用 SKILL_ROUTER_AGENT，仍未提供则使用 codex。
        """ + "\n"
    }
}

private struct ParsedArguments {
    var path: String?
    var target: String?
    var all = false
    var positionals: [String] = []

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--path":
                guard index + 1 < arguments.count else { throw CLIUsageError("--path 缺少值") }
                path = arguments[index + 1]
                index += 2
            case "--target":
                guard index + 1 < arguments.count else { throw CLIUsageError("--target 缺少值") }
                let value = arguments[index + 1]
                guard !value.isEmpty, !value.hasPrefix("-") else { throw CLIUsageError("--target 值无效") }
                target = value
                index += 2
            case "--all":
                all = true
                index += 1
            case let value where value.hasPrefix("-"):
                throw CLIUsageError("未知选项：\(value)")
            default:
                positionals.append(arguments[index])
                index += 1
            }
        }
    }

    func requireNoPositionals() throws {
        if !positionals.isEmpty { throw CLIUsageError("该命令不接受位置参数") }
    }
}

private struct CLIUsageError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private struct CLIEnvelope<T: Encodable>: Encodable {
    let schemaVersion: Int
    let command: String
    let success: Bool
    let exitCode: Int32
    let data: T
}

private struct CLIErrorEnvelope: Encodable {
    let schemaVersion: Int
    let command: String
    let success: Bool
    let exitCode: Int32
    let error: String
}

private struct EmptyOutput: Encodable {}

private struct RegisterOutput: Encodable {
    let path: String
    let targetID: String
    let targetPath: String
}

private struct ProjectListOutput: Encodable {
    let projects: [String]
}
