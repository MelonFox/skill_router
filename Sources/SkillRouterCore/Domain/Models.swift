import Foundation

public enum ManagedSkillOrigin: String, Codable, Sendable {
    case local
    case git
}

public struct ManagedSkillRecord: Codable, Equatable, Sendable {
    public let name: SkillName
    public let origin: ManagedSkillOrigin
    public let suiteName: SuiteName?
    public let sourceID: UUID?
    public let contentRelativePath: String
    public let importedAt: Date

    public init(
        name: SkillName,
        origin: ManagedSkillOrigin,
        suiteName: SuiteName?,
        sourceID: UUID?,
        contentRelativePath: String,
        importedAt: Date
    ) {
        self.name = name
        self.origin = origin
        self.suiteName = suiteName
        self.sourceID = sourceID
        self.contentRelativePath = contentRelativePath
        self.importedAt = importedAt
    }
}

public struct SkillSuiteRecord: Codable, Equatable, Sendable {
    public let name: SuiteName
    public let origin: ManagedSkillOrigin
    public let sourceID: UUID?
    public var skills: [SkillName]
    public let createdAt: Date

    public init(
        name: SuiteName,
        origin: ManagedSkillOrigin,
        sourceID: UUID?,
        skills: [SkillName],
        createdAt: Date
    ) {
        self.name = name
        self.origin = origin
        self.sourceID = sourceID
        self.skills = skills.sorted()
        self.createdAt = createdAt
    }
}

public struct GitSourceRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let remoteURL: String
    public var suiteName: SuiteName?
    public var selectedSkills: [SkillName]
    public var lastAppliedCommit: String
    public var availableCommit: String?
    public var lastCheckedAt: Date?

    public init(
        id: UUID,
        remoteURL: String,
        suiteName: SuiteName?,
        selectedSkills: [SkillName],
        lastAppliedCommit: String,
        availableCommit: String? = nil,
        lastCheckedAt: Date? = nil
    ) {
        self.id = id
        self.remoteURL = remoteURL
        self.suiteName = suiteName
        self.selectedSkills = selectedSkills.sorted()
        self.lastAppliedCommit = lastAppliedCommit
        self.availableCommit = availableCommit
        self.lastCheckedAt = lastCheckedAt
    }
}

public struct RegisteredProjectRecord: Codable, Equatable, Sendable {
    public let path: String
    public var bookmarkData: Data?
    public let registeredAt: Date

    public init(path: String, bookmarkData: Data? = nil, registeredAt: Date) {
        self.path = path
        self.bookmarkData = bookmarkData
        self.registeredAt = registeredAt
    }
}

public struct SystemSkillSettings: Codable, Equatable, Sendable {
    public var codexEnabled: Bool
    public var claudeCodeEnabled: Bool

    public init(codexEnabled: Bool = true, claudeCodeEnabled: Bool = true) {
        self.codexEnabled = codexEnabled
        self.claudeCodeEnabled = claudeCodeEnabled
    }
}

public struct RouterState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var skills: [ManagedSkillRecord]
    public var suites: [SkillSuiteRecord]
    public var gitSources: [GitSourceRecord]
    public var projects: [RegisteredProjectRecord]
    public var systemSkill: SystemSkillSettings
    public var lastAutomaticUpdateCheckAt: Date?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        skills: [ManagedSkillRecord] = [],
        suites: [SkillSuiteRecord] = [],
        gitSources: [GitSourceRecord] = [],
        projects: [RegisteredProjectRecord] = [],
        systemSkill: SystemSkillSettings = SystemSkillSettings(),
        lastAutomaticUpdateCheckAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.skills = skills.sorted { $0.name < $1.name }
        self.suites = suites.sorted { $0.name < $1.name }
        self.gitSources = gitSources.sorted { $0.id.uuidString < $1.id.uuidString }
        self.projects = projects.sorted { $0.path < $1.path }
        self.systemSkill = systemSkill
        self.lastAutomaticUpdateCheckAt = lastAutomaticUpdateCheckAt
    }

    public mutating func normalize() {
        skills.sort { $0.name < $1.name }
        suites = suites.map {
            var value = $0
            value.skills.sort()
            return value
        }.sorted { $0.name < $1.name }
        gitSources = gitSources.map {
            var value = $0
            value.selectedSkills.sort()
            return value
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        projects.sort { $0.path < $1.path }
    }

    public func skill(named name: SkillName) -> ManagedSkillRecord? {
        skills.first { $0.name == name }
    }
}

public enum DistributionTargetKind: String, Codable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case custom
}

public struct DistributionTargetRecord: Codable, Equatable, Sendable {
    public let type: DistributionTargetKind
    public let path: String

    public init(type: DistributionTargetKind, path: String) throws {
        try Self.validateRelativePath(path)
        self.type = type
        self.path = path
    }

    public static var codex: DistributionTargetRecord {
        try! DistributionTargetRecord(type: .codex, path: ".agents/skills")
    }

    public static var claudeCode: DistributionTargetRecord {
        try! DistributionTargetRecord(type: .claudeCode, path: ".claude/skills")
    }

    private static func validateRelativePath(_ path: String) throws {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !components.contains(".."),
              !components.contains("") else {
            throw SkillRouterError.io("分发目标必须是规范的项目相对路径：\(path)")
        }
    }
}

public struct DesiredSkillAssignment: Codable, Equatable, Sendable {
    public var targets: [String]

    public init(targets: [String]) {
        self.targets = Array(Set(targets)).sorted()
    }
}

public struct ProjectManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var targets: [String: DistributionTargetRecord]
    public var skills: [String: DesiredSkillAssignment]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        targets: [String: DistributionTargetRecord] = [:],
        skills: [String: DesiredSkillAssignment] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.targets = targets
        self.skills = skills
    }

    public mutating func normalize() {
        skills = skills.mapValues { DesiredSkillAssignment(targets: $0.targets) }
    }

    public func validate() throws {
        for (name, assignment) in skills {
            _ = try SkillName(rawValue: name)
            for target in assignment.targets where targets[target] == nil {
                throw SkillRouterError.io("Skill \(name) 引用了不存在的目标：\(target)")
            }
        }
    }
}

public enum ArtifactEntryKind: String, Codable, Sendable {
    case file
    case symbolicLink
}

public struct ArtifactFileRecord: Codable, Equatable, Sendable {
    public let path: String
    public let kind: ArtifactEntryKind
    public let sha256: String
    public let byteCount: Int64

    public init(path: String, kind: ArtifactEntryKind, sha256: String, byteCount: Int64) {
        self.path = path
        self.kind = kind
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public struct ArtifactManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var skills: [ManagedSkillRecord]
    public var suites: [SkillSuiteRecord]
    public var gitSources: [GitSourceRecord]
    public var files: [ArtifactFileRecord]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        skills: [ManagedSkillRecord],
        suites: [SkillSuiteRecord],
        gitSources: [GitSourceRecord],
        files: [ArtifactFileRecord]
    ) {
        self.schemaVersion = schemaVersion
        self.skills = skills.sorted { $0.name < $1.name }
        self.suites = suites.sorted { $0.name < $1.name }
        self.gitSources = gitSources.sorted { $0.id.uuidString < $1.id.uuidString }
        self.files = files.sorted { $0.path < $1.path }
    }
}
