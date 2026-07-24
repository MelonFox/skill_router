import Foundation

public struct ZipTool: Sendable {
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func validateEntryPaths(_ entries: [String]) throws {
        var seen = Set<String>()
        for entry in entries {
            let normalized = entry.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
            if normalized.hasPrefix("/") ||
                normalized.contains("\0") ||
                components.contains("..") ||
                components.first?.contains(":") == true {
                throw SkillRouterError.invalidArchivePath(entry)
            }
            guard seen.insert(normalized).inserted else {
                throw SkillRouterError.invalidArchivePath("重复路径：\(entry)")
            }
        }
    }

    public func listEntries(in archive: URL) throws -> [String] {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zipinfo"),
            arguments: ["-1", archive.path]
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: "/usr/bin/zipinfo",
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let entries = result.outputString.split(separator: "\n").map(String.init)
        try validateEntryPaths(entries)
        return entries
    }

    public func createArchive(from directory: URL, at destination: URL) throws {
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", "--keepParent", "--norsrc", directory.path, destination.path]
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: "/usr/bin/ditto",
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func createDeterministicArchive(contentsOf directory: URL, at destination: URL) throws {
        try normalizeModificationDates(in: directory)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-X", "-q", "-y", "-r", destination.path, "."],
            currentDirectory: directory,
            environment: ["COPYFILE_DISABLE": "1"]
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: "/usr/bin/zip",
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func extractArchive(_ archive: URL, to directory: URL) throws {
        _ = try listEntries(in: archive)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", "--norsrc", archive.path, directory.path]
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: "/usr/bin/ditto",
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func normalizeModificationDates(in root: URL) throws {
        let fixedDate = Date(timeIntervalSince1970: 315_532_800)
        var urls = [root]
        if let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) {
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    enumerator.skipDescendants()
                }
                urls.append(url)
            }
        }
        for url in urls.sorted(by: { $0.path > $1.path }) {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        }
    }
}
