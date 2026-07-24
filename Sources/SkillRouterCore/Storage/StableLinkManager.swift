import Foundation

public struct StableLinkManager {
    private let paths: RouterPaths
    private let fileManager: FileManager

    public init(paths: RouterPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func rebuild(for state: RouterState) throws {
        try fileManager.createDirectory(at: paths.linksDirectory, withIntermediateDirectories: true)
        let expectedNames = Set(state.skills.map { $0.name.rawValue })

        if let entries = try? fileManager.contentsOfDirectory(
            at: paths.linksDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) {
            for entry in entries where !expectedNames.contains(entry.lastPathComponent) {
                if isManagedStableLink(entry) {
                    try fileManager.removeItem(at: entry)
                }
            }
        }

        for skill in state.skills {
            let link = paths.stableLink(skill.name)
            let expectedDestination = "../\(skill.contentRelativePath)"
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: link.path, isDirectory: &isDirectory)
            let isSymlink = (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true

            if exists || isSymlink {
                guard isSymlink else {
                    throw SkillRouterError.unmanagedPathConflict(link.path)
                }
                let current = try fileManager.destinationOfSymbolicLink(atPath: link.path)
                if current == expectedDestination { continue }
                try fileManager.removeItem(at: link)
            }
            try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: expectedDestination)
        }
    }

    private func isManagedStableLink(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true,
              let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return false
        }
        return destination.hasPrefix("../Library/Skills/") || destination.hasPrefix("../Library/Suites/")
    }
}
