import Foundation

public struct GitClient: Sendable {
    private let runner: ProcessRunner
    private let executable = URL(fileURLWithPath: "/usr/bin/git")

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func cloneDefaultBranch(from remote: String, to destination: URL) throws {
        let result = try runner.run(
            executable: executable,
            arguments: ["clone", "--depth", "1", "--single-branch", "--", remote, destination.path]
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: executable.path,
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    public func cloneDefaultBranchMetadata(from remote: String, to destination: URL) throws {
        let result = try runner.run(
            executable: executable,
            arguments: [
                "-c", "http.lowSpeedLimit=1",
                "-c", "http.lowSpeedTime=60",
                "clone", "--depth", "1", "--single-branch",
                "--filter=blob:none", "--no-checkout", "--",
                remote, destination.path
            ]
        )
        try requireSuccess(result)
    }

    public func trackedFiles(in repository: URL) throws -> [String] {
        let result = try runner.run(
            executable: executable,
            arguments: ["ls-tree", "-r", "--name-only", "-z", "HEAD"],
            currentDirectory: repository
        )
        try requireSuccess(result)
        return result.outputString
            .split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
            .sorted()
    }

    public func fileContents(at path: String, in repository: URL) throws -> String {
        let result = try runner.run(
            executable: executable,
            arguments: ["show", "HEAD:\(path)"],
            currentDirectory: repository
        )
        try requireSuccess(result)
        return result.outputString
    }

    public func checkout(paths: [String], in repository: URL) throws {
        let uniquePaths = Array(Set(paths)).sorted()
        guard !uniquePaths.isEmpty else { return }

        if uniquePaths.contains(".") {
            let result = try runner.run(
                executable: executable,
                arguments: ["checkout", "--force", "HEAD"],
                currentDirectory: repository
            )
            try requireSuccess(result)
            return
        }

        var result = try runner.run(
            executable: executable,
            arguments: ["sparse-checkout", "init", "--cone"],
            currentDirectory: repository
        )
        try requireSuccess(result)
        result = try runner.run(
            executable: executable,
            arguments: ["sparse-checkout", "set", "--"] + uniquePaths,
            currentDirectory: repository
        )
        try requireSuccess(result)
        result = try runner.run(
            executable: executable,
            arguments: ["checkout", "--force", "HEAD"],
            currentDirectory: repository
        )
        try requireSuccess(result)
    }

    public func headCommit(in repository: URL) throws -> String {
        let result = try runner.run(
            executable: executable,
            arguments: ["rev-parse", "HEAD"],
            currentDirectory: repository
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: executable.path,
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.outputString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func remoteHead(_ remote: String) throws -> String {
        let result = try runner.run(
            executable: executable,
            arguments: [
                "-c", "http.lowSpeedLimit=1",
                "-c", "http.lowSpeedTime=60",
                "ls-remote", "--", remote, "HEAD"
            ]
        )
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: executable.path,
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard let commit = result.outputString.split(whereSeparator: { $0 == "\t" || $0 == " " }).first,
              commit.count == 40 else {
            throw SkillRouterError.processFailed(
                executable: executable.path,
                exitCode: result.exitCode,
                diagnostic: "远端没有可解析的默认分支 HEAD"
            )
        }
        return String(commit)
    }

    private func requireSuccess(_ result: ProcessResult) throws {
        guard result.exitCode == 0 else {
            throw SkillRouterError.processFailed(
                executable: executable.path,
                exitCode: result.exitCode,
                diagnostic: result.errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
