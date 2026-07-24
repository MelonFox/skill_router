import Foundation

struct GitTreeSkillCandidate: Equatable, Sendable {
    let name: SkillName
    let relativeDirectory: String
    let manifest: ParsedSkillManifest
}

struct GitTreeSkillDiscovery: Sendable {
    private struct ParsedCandidate {
        let candidate: GitTreeSkillCandidate
        let manifestContent: String
    }

    private static let excludedDirectoryNames: Set<String> = [
        ".git", ".hg", ".svn", ".swiftpm", ".build", "build", "dist",
        "node_modules", "Pods", "DerivedData", "vendor", "coverage"
    ]

    private let git: GitClient
    private let parser: SkillManifestParser

    init(git: GitClient, parser: SkillManifestParser = SkillManifestParser()) {
        self.git = git
        self.parser = parser
    }

    func discover(in repository: URL) throws -> [GitTreeSkillCandidate] {
        let manifestPaths = try git.trackedFiles(in: repository).filter(isCandidateManifest)
        var candidates: [ParsedCandidate] = []
        for manifestPath in manifestPaths {
            let content = try git.fileContents(at: manifestPath, in: repository)
            let manifest = try parser.parse(content)
            let directory = (manifestPath as NSString).deletingLastPathComponent
            candidates.append(ParsedCandidate(
                candidate: GitTreeSkillCandidate(
                    name: manifest.name,
                    relativeDirectory: directory.isEmpty ? "." : directory,
                    manifest: manifest
                ),
                manifestContent: content
            ))
        }

        var resolved: [GitTreeSkillCandidate] = []
        for group in Dictionary(grouping: candidates, by: { $0.candidate.name }).values {
            if group.count == 1 {
                resolved.append(group[0].candidate)
                continue
            }
            resolved.append(try resolveMirroredCandidates(group))
        }
        return resolved.sorted { $0.name < $1.name }
    }

    private func isCandidateManifest(_ path: String) -> Bool {
        guard (path as NSString).lastPathComponent == "SKILL.md" else { return false }
        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty else { return true }
        return directory.split(separator: "/").allSatisfy { component in
            let value = String(component)
            return !value.hasPrefix(".") && !Self.excludedDirectoryNames.contains(value)
        }
    }

    private func resolveMirroredCandidates(_ group: [ParsedCandidate]) throws -> GitTreeSkillCandidate {
        let name = group[0].candidate.name
        let contents = Set(group.map(\.manifestContent))
        let scored = group.map { ($0, packagingScore($0.candidate)) }
        let highestScore = scored.map(\.1).max() ?? 0
        let preferred = scored.filter { $0.1 == highestScore }

        if contents.count == 1, highestScore > 0, preferred.count == 1 {
            return preferred[0].0.candidate
        }

        let paths = group.map { candidate in
            candidate.candidate.relativeDirectory == "."
                ? "SKILL.md"
                : "\(candidate.candidate.relativeDirectory)/SKILL.md"
        }.sorted().joined(separator: "、")
        throw SkillRouterError.io("来源中存在重复 Skill 名称：\(name.rawValue)（\(paths)）")
    }

    private func packagingScore(_ candidate: GitTreeSkillCandidate) -> Int {
        let components = candidate.relativeDirectory.split(separator: "/").map(String.init)
        guard components.count >= 2,
              components[components.count - 2] == "skills",
              components.last == candidate.name.rawValue else {
            return 0
        }
        return 100 + components.count
    }
}
