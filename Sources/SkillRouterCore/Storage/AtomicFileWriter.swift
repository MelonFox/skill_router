import Darwin
import Foundation

public struct AtomicFileWriter: Sendable {
    public init() {}

    public func write(_ data: Data, to destination: URL) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            let descriptor = open(temporary.path, O_RDONLY)
            if descriptor >= 0 {
                _ = fsync(descriptor)
                close(descriptor)
            }
            guard rename(temporary.path, destination.path) == 0 else {
                throw SkillRouterError.io("原子替换失败：\(destination.path)，errno=\(errno)")
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            if let routerError = error as? SkillRouterError {
                throw routerError
            }
            throw SkillRouterError.io(error.localizedDescription)
        }
    }
}
