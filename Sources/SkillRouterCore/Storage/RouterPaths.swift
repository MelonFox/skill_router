import Foundation

public struct RouterPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public static func production(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> RouterPaths {
        if let override = environment["SKILL_ROUTER_HOME"], !override.isEmpty {
            return RouterPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        return RouterPaths(root: homeDirectory.appendingPathComponent(".skill-router", isDirectory: true))
    }

    public var stateFile: URL { root.appendingPathComponent("state.json") }
    public var lockFile: URL { root.appendingPathComponent("state.lock") }
    public var journalDirectory: URL { root.appendingPathComponent("Journal", isDirectory: true) }
    public var stagingDirectory: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    public var standaloneSkillsDirectory: URL { root.appendingPathComponent("Library/Skills", isDirectory: true) }
    public var suitesDirectory: URL { root.appendingPathComponent("Library/Suites", isDirectory: true) }
    public var linksDirectory: URL { root.appendingPathComponent("links", isDirectory: true) }
    public var sourcesDirectory: URL { root.appendingPathComponent("Sources", isDirectory: true) }
    public var systemSkillsDirectory: URL { root.appendingPathComponent("system-skills", isDirectory: true) }
    public var binDirectory: URL { root.appendingPathComponent("bin", isDirectory: true) }

    public func standaloneSkill(_ name: SkillName) -> URL {
        standaloneSkillsDirectory.appendingPathComponent(name.rawValue, isDirectory: true)
    }

    public func suite(_ name: SuiteName) -> URL {
        suitesDirectory.appendingPathComponent(name.rawValue, isDirectory: true)
    }

    public func stableLink(_ name: SkillName) -> URL {
        linksDirectory.appendingPathComponent(name.rawValue)
    }

    public func createBaseDirectories(fileManager: FileManager = .default) throws {
        let directories = [
            root,
            journalDirectory,
            stagingDirectory,
            standaloneSkillsDirectory,
            suitesDirectory,
            linksDirectory,
            sourcesDirectory,
            systemSkillsDirectory,
            binDirectory
        ]
        do {
            for directory in directories {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            throw SkillRouterError.io(error.localizedDescription)
        }
    }

    public func createInfrastructureDirectories(fileManager: FileManager = .default) throws {
        let directories = [
            root,
            journalDirectory,
            stagingDirectory,
            linksDirectory,
            sourcesDirectory,
            systemSkillsDirectory,
            binDirectory
        ]
        do {
            for directory in directories {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            throw SkillRouterError.io(error.localizedDescription)
        }
    }
}
