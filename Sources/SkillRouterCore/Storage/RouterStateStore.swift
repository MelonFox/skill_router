import Foundation

public final class RouterStateStore: @unchecked Sendable {
    public let paths: RouterPaths
    private let codec: VersionedJSONCodec
    private let writer: AtomicFileWriter

    public init(
        paths: RouterPaths,
        codec: VersionedJSONCodec = VersionedJSONCodec(),
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        self.paths = paths
        self.codec = codec
        self.writer = writer
    }

    public func initializeIfNeeded() throws {
        if FileManager.default.fileExists(atPath: paths.stateFile.path) {
            try paths.createInfrastructureDirectories()
            return
        }
        try paths.createBaseDirectories()
        try writer.write(codec.encode(RouterState()), to: paths.stateFile)
    }

    public func load() throws -> RouterState {
        try initializeIfNeeded()
        do {
            return try codec.decodeRouterState(Data(contentsOf: paths.stateFile))
        } catch let error as SkillRouterError {
            throw error
        } catch {
            throw SkillRouterError.io(error.localizedDescription)
        }
    }

    public func save(_ state: RouterState) throws {
        var normalized = state
        normalized.normalize()
        try writer.write(codec.encode(normalized), to: paths.stateFile)
    }

    @discardableResult
    public func withExclusiveState<T>(
        timeout: Duration = .seconds(5),
        _ operation: (inout RouterState) throws -> T
    ) throws -> T {
        try initializeIfNeeded()
        let lock = try FileLock(url: paths.lockFile)
        return try lock.withLock(timeout: timeout) {
            var state = try load()
            let result = try operation(&state)
            try save(state)
            return result
        }
    }
}
