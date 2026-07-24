import Foundation

public enum ReconciliationStatus: String, Codable, Sendable {
    case installed
    case alreadyCorrect
    case repaired
    case removed
    case conflict
    case missingCentralSkill
}

public struct ReconciliationItem: Codable, Equatable, Sendable {
    public let skillName: String
    public let targetID: String
    public let status: ReconciliationStatus
    public let detail: String?

    public init(skillName: String, targetID: String, status: ReconciliationStatus, detail: String? = nil) {
        self.skillName = skillName
        self.targetID = targetID
        self.status = status
        self.detail = detail
    }
}

public struct ReconciliationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var items: [ReconciliationItem]

    public init(schemaVersion: Int = 1, items: [ReconciliationItem]) {
        self.schemaVersion = schemaVersion
        self.items = items.sorted {
            ($0.targetID, $0.skillName, $0.status.rawValue) < ($1.targetID, $1.skillName, $1.status.rawValue)
        }
    }

    public var hasFailures: Bool {
        items.contains { $0.status == .conflict || $0.status == .missingCentralSkill }
    }
}

public struct ProjectReconciler {
    private let paths: RouterPaths
    private let fileManager: FileManager

    public init(paths: RouterPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func reconcile(project: URL, manifest: ProjectManifest, state: RouterState) throws -> ReconciliationReport {
        var items: [ReconciliationItem] = []
        let centralNames = Set(state.skills.map { $0.name.rawValue })

        for targetID in manifest.targets.keys.sorted() {
            guard let target = manifest.targets[targetID] else { continue }
            let targetDirectory = project.appendingPathComponent(target.path, isDirectory: true)
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

            let desiredNames = Set(manifest.skills.compactMap { name, assignment in
                assignment.targets.contains(targetID) ? name : nil
            })

            for name in desiredNames.sorted() {
                guard centralNames.contains(name), let skillName = try? SkillName(rawValue: name) else {
                    items.append(ReconciliationItem(
                        skillName: name,
                        targetID: targetID,
                        status: .missingCentralSkill,
                        detail: "中央库不存在该 Skill"
                    ))
                    continue
                }
                let destination = targetDirectory.appendingPathComponent(name)
                let expected = paths.stableLink(skillName).path
                let status = try ensureProjectLink(at: destination, expectedDestination: expected)
                items.append(ReconciliationItem(skillName: name, targetID: targetID, status: status.0, detail: status.1))
            }

            let entries = (try? fileManager.contentsOfDirectory(
                at: targetDirectory,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries where !desiredNames.contains(entry.lastPathComponent) {
                guard isManagedProjectLink(entry) else { continue }
                try fileManager.removeItem(at: entry)
                items.append(ReconciliationItem(
                    skillName: entry.lastPathComponent,
                    targetID: targetID,
                    status: .removed
                ))
            }
        }

        return ReconciliationReport(items: items)
    }

    private func ensureProjectLink(
        at destination: URL,
        expectedDestination: String
    ) throws -> (ReconciliationStatus, String?) {
        let isSymlink = (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        if isSymlink {
            let current = try fileManager.destinationOfSymbolicLink(atPath: destination.path)
            if current == expectedDestination {
                return (.alreadyCorrect, nil)
            }
            if isRouterLinkDestination(current, expectedName: destination.lastPathComponent) {
                try fileManager.removeItem(at: destination)
                try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: expectedDestination)
                return (.repaired, "已修复损坏的受管链接")
            }
            return (.conflict, "存在不受管软链接：\(destination.path)")
        }

        if fileManager.fileExists(atPath: destination.path) {
            return (.conflict, "存在不受管文件或目录：\(destination.path)")
        }
        try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: expectedDestination)
        return (.installed, nil)
    }

    private func isManagedProjectLink(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return false
        }
        return isRouterLinkDestination(destination, expectedName: url.lastPathComponent)
    }

    private func isRouterLinkDestination(_ destination: String, expectedName: String) -> Bool {
        let expected = paths.linksDirectory.appendingPathComponent(expectedName).standardizedFileURL.path
        return URL(fileURLWithPath: destination).standardizedFileURL.path == expected
    }
}
