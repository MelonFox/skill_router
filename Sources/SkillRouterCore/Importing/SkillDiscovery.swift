import Foundation

public struct SkillCandidate: Equatable, Sendable {
    public let name: SkillName
    public let directory: URL
    public let manifest: ParsedSkillManifest

    public init(name: SkillName, directory: URL, manifest: ParsedSkillManifest) {
        self.name = name
        self.directory = directory
        self.manifest = manifest
    }
}

public struct SkillDiscovery {
    private static let excludedDirectoryNames: Set<String> = [
        ".git", ".hg", ".svn", ".swiftpm", ".build", "build", "dist",
        "node_modules", "Pods", "DerivedData", "vendor", "coverage"
    ]

    private let parser: SkillManifestParser
    private let fileManager: FileManager

    public init(parser: SkillManifestParser = SkillManifestParser(), fileManager: FileManager = .default) {
        self.parser = parser
        self.fileManager = fileManager
    }

    public func discover(in root: URL) throws -> [SkillCandidate] {
        var candidates: [SkillCandidate] = []
        var seenNames = Set<SkillName>()

        if let candidate = try candidate(at: root) {
            candidates.append(candidate)
            seenNames.insert(candidate.name)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else {
            throw SkillRouterError.io("无法扫描目录：\(root.path)")
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true else { continue }
            if values.isSymbolicLink == true || Self.excludedDirectoryNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if let candidate = try candidate(at: url) {
                guard seenNames.insert(candidate.name).inserted else {
                    throw SkillRouterError.io("来源中存在重复 Skill 名称：\(candidate.name.rawValue)")
                }
                candidates.append(candidate)
                enumerator.skipDescendants()
            }
        }
        return candidates.sorted { $0.name < $1.name }
    }

    private func candidate(at directory: URL) throws -> SkillCandidate? {
        let manifestURL = directory.appendingPathComponent("SKILL.md")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest = try parser.parse(fileAt: manifestURL)
        return SkillCandidate(name: manifest.name, directory: directory, manifest: manifest)
    }
}
