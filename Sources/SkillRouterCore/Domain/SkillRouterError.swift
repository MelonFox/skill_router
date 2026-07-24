import Foundation

public enum SkillRouterError: Error, Equatable, Sendable {
    case invalidSkillName(String)
    case invalidSuiteName(String)
    case malformedSkillManifest(String)
    case unsupportedSchema(document: String, version: Int)
    case stateBusy
    case unmanagedPathConflict(String)
    case missingSkill(String)
    case invalidArchivePath(String)
    case invalidJSON(String)
    case processFailed(executable: String, exitCode: Int32, diagnostic: String)
    case io(String)
}

extension SkillRouterError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSkillName(let name):
            return "Skill 名称不合法：\(name)"
        case .invalidSuiteName(let name):
            return "套件名称不合法：\(name)"
        case .malformedSkillManifest(let reason):
            return "SKILL.md 无法解析：\(reason)"
        case .unsupportedSchema(let document, let version):
            return "不支持的 \(document) schemaVersion：\(version)"
        case .stateBusy:
            return "Skill Router 正忙，请稍后重试"
        case .unmanagedPathConflict(let path):
            return "目标存在不受 Skill Router 管理的同名项目：\(path)"
        case .missingSkill(let name):
            return "中央库不存在 Skill：\(name)"
        case .invalidArchivePath(let path):
            return "归档包含不安全路径：\(path)"
        case .invalidJSON(let reason):
            return "JSON 无法解析：\(reason)"
        case .processFailed(let executable, let exitCode, let diagnostic):
            return "命令执行失败（\(executable)，退出码 \(exitCode)）：\(diagnostic)"
        case .io(let message):
            return "文件系统操作失败：\(message)"
        }
    }
}
