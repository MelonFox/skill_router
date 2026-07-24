import Foundation
import SkillRouterCLIKit

let execution = SkillRouterCLI().run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    environment: ProcessInfo.processInfo.environment,
    currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
)

if !execution.standardOutput.isEmpty {
    FileHandle.standardOutput.write(Data(execution.standardOutput.utf8))
}
if !execution.standardError.isEmpty {
    FileHandle.standardError.write(Data(execution.standardError.utf8))
}
exit(execution.exitCode)
