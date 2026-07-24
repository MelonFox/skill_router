import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public var outputString: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    public var errorString: String {
        String(decoding: standardError, as: UTF8.self)
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        if let environment {
            process.environment = environment
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SkillRouterError.io("无法启动 \(executable.path)：\(error.localizedDescription)")
        }

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout.fileHandleForReading.readDataToEndOfFile(),
            standardError: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }
}
