import Darwin
import Foundation

public final class FileLock: @unchecked Sendable {
    private let descriptor: Int32
    private var isLocked = false

    public init(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw SkillRouterError.io("无法打开锁文件：\(url.path)，errno=\(errno)")
        }
    }

    deinit {
        if isLocked {
            _ = flock(descriptor, LOCK_UN)
        }
        close(descriptor)
    }

    public func lock(timeout: Duration = .seconds(5), pollInterval: Duration = .milliseconds(25)) throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                isLocked = true
                return
            }
            guard errno == EWOULDBLOCK else {
                throw SkillRouterError.io("无法取得状态锁，errno=\(errno)")
            }
            guard clock.now < deadline else {
                throw SkillRouterError.stateBusy
            }
            Thread.sleep(forTimeInterval: max(0.001, pollInterval.timeInterval))
        }
    }

    public func unlock() {
        guard isLocked else { return }
        _ = flock(descriptor, LOCK_UN)
        isLocked = false
    }

    public func withLock<T>(
        timeout: Duration = .seconds(5),
        _ operation: () throws -> T
    ) throws -> T {
        try lock(timeout: timeout)
        defer { unlock() }
        return try operation()
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
