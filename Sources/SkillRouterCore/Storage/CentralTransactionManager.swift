import Darwin
import Foundation

public enum CentralTransactionCheckpoint: String, Sendable {
    case afterJournalPrepared
    case afterOldLibraryMoved
    case afterNewLibraryInstalled
    case afterStateSaved
}

private enum CentralTransactionPhase: String, Codable {
    case prepared
    case oldLibraryMoved
    case newLibraryInstalled
    case stateSaved
}

private struct CentralTransactionJournal: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    var phase: CentralTransactionPhase
    let transactionDirectoryName: String
    let encodedState: Data
}

public final class CentralTransactionManager: @unchecked Sendable {
    public typealias FailureInjector = @Sendable (CentralTransactionCheckpoint) throws -> Void

    private let store: RouterStateStore
    private let codec: VersionedJSONCodec
    private let writer: AtomicFileWriter
    private let fileManager: FileManager
    private let failureInjector: FailureInjector?

    public init(
        store: RouterStateStore,
        codec: VersionedJSONCodec = VersionedJSONCodec(),
        writer: AtomicFileWriter = AtomicFileWriter(),
        fileManager: FileManager = .default,
        failureInjector: FailureInjector? = nil
    ) {
        self.store = store
        self.codec = codec
        self.writer = writer
        self.fileManager = fileManager
        self.failureInjector = failureInjector
    }

    @discardableResult
    public func perform<T>(
        _ operation: (inout RouterState, URL) throws -> T
    ) throws -> T {
        try store.initializeIfNeeded()
        let lock = try FileLock(url: store.paths.lockFile)
        return try lock.withLock {
            try recoverLocked()
            var state = try store.load()
            let transactionID = UUID()
            let transactionDirectory = store.paths.stagingDirectory
                .appendingPathComponent(transactionID.uuidString, isDirectory: true)
            let stagedLibrary = transactionDirectory.appendingPathComponent("Library.new", isDirectory: true)
            try fileManager.createDirectory(at: transactionDirectory, withIntermediateDirectories: true)

            do {
                if fileManager.fileExists(atPath: store.paths.root.appendingPathComponent("Library").path) {
                    try fileManager.copyItem(
                        at: store.paths.root.appendingPathComponent("Library", isDirectory: true),
                        to: stagedLibrary
                    )
                } else {
                    try fileManager.createDirectory(at: stagedLibrary, withIntermediateDirectories: true)
                }

                let result = try operation(&state, stagedLibrary)
                state.normalize()
                let journal = CentralTransactionJournal(
                    schemaVersion: CentralTransactionJournal.currentSchemaVersion,
                    id: transactionID,
                    phase: .prepared,
                    transactionDirectoryName: transactionID.uuidString,
                    encodedState: try codec.encode(state)
                )
                try writeJournal(journal)
                try failureInjector?(.afterJournalPrepared)

                try installStagedLibrary(journal)

                var installed = journal
                installed.phase = .newLibraryInstalled
                try writeJournal(installed)
                try failureInjector?(.afterNewLibraryInstalled)

                try store.save(state)
                installed.phase = .stateSaved
                try writeJournal(installed)
                try failureInjector?(.afterStateSaved)

                try StableLinkManager(paths: store.paths, fileManager: fileManager).rebuild(for: state)
                try cleanup(installed)
                return result
            } catch {
                if !journalExists(for: transactionID) {
                    try? fileManager.removeItem(at: transactionDirectory)
                }
                throw error
            }
        }
    }

    public func recoverPendingTransactions() throws {
        try store.initializeIfNeeded()
        let lock = try FileLock(url: store.paths.lockFile)
        try lock.withLock {
            try recoverLocked()
        }
    }

    private func recoverLocked() throws {
        let journalFiles = (try? fileManager.contentsOfDirectory(
            at: store.paths.journalDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        for journalURL in journalFiles {
            let journal: CentralTransactionJournal
            do {
                journal = try decodeJournal(Data(contentsOf: journalURL))
            } catch {
                throw SkillRouterError.io("事务日志损坏，已停止写入：\(journalURL.path)")
            }

            switch journal.phase {
            case .prepared:
                try cleanup(journal)
            case .oldLibraryMoved:
                try finishOrRollbackOldMove(journal)
            case .newLibraryInstalled:
                let state = try codec.decodeRouterState(journal.encodedState)
                try store.save(state)
                var updated = journal
                updated.phase = .stateSaved
                try writeJournal(updated)
                try StableLinkManager(paths: store.paths, fileManager: fileManager).rebuild(for: state)
                try cleanup(updated)
            case .stateSaved:
                let state = try codec.decodeRouterState(journal.encodedState)
                try StableLinkManager(paths: store.paths, fileManager: fileManager).rebuild(for: state)
                try cleanup(journal)
            }
        }
    }

    private func installStagedLibrary(_ journal: CentralTransactionJournal) throws {
        let finalLibrary = store.paths.root.appendingPathComponent("Library", isDirectory: true)
        let transactionDirectory = store.paths.stagingDirectory
            .appendingPathComponent(journal.transactionDirectoryName, isDirectory: true)
        let stagedLibrary = transactionDirectory.appendingPathComponent("Library.new", isDirectory: true)
        let backupLibrary = transactionDirectory.appendingPathComponent("Library.old", isDirectory: true)

        if fileManager.fileExists(atPath: finalLibrary.path) {
            try renameItem(finalLibrary, to: backupLibrary)
        }
        var moved = journal
        moved.phase = .oldLibraryMoved
        try writeJournal(moved)
        try failureInjector?(.afterOldLibraryMoved)
        try renameItem(stagedLibrary, to: finalLibrary)
    }

    private func finishOrRollbackOldMove(_ journal: CentralTransactionJournal) throws {
        let finalLibrary = store.paths.root.appendingPathComponent("Library", isDirectory: true)
        let transactionDirectory = store.paths.stagingDirectory
            .appendingPathComponent(journal.transactionDirectoryName, isDirectory: true)
        let stagedLibrary = transactionDirectory.appendingPathComponent("Library.new", isDirectory: true)
        let backupLibrary = transactionDirectory.appendingPathComponent("Library.old", isDirectory: true)

        if !fileManager.fileExists(atPath: finalLibrary.path), fileManager.fileExists(atPath: stagedLibrary.path) {
            try renameItem(stagedLibrary, to: finalLibrary)
            var updated = journal
            updated.phase = .newLibraryInstalled
            try writeJournal(updated)
            let state = try codec.decodeRouterState(updated.encodedState)
            try store.save(state)
            updated.phase = .stateSaved
            try writeJournal(updated)
            try StableLinkManager(paths: store.paths, fileManager: fileManager).rebuild(for: state)
            try cleanup(updated)
            return
        }

        if fileManager.fileExists(atPath: finalLibrary.path),
           !fileManager.fileExists(atPath: stagedLibrary.path),
           fileManager.fileExists(atPath: backupLibrary.path) {
            var updated = journal
            updated.phase = .newLibraryInstalled
            try writeJournal(updated)
            let state = try codec.decodeRouterState(updated.encodedState)
            try store.save(state)
            updated.phase = .stateSaved
            try writeJournal(updated)
            try StableLinkManager(paths: store.paths, fileManager: fileManager).rebuild(for: state)
            try cleanup(updated)
            return
        }

        if !fileManager.fileExists(atPath: finalLibrary.path), fileManager.fileExists(atPath: backupLibrary.path) {
            try renameItem(backupLibrary, to: finalLibrary)
            try cleanup(journal)
            return
        }

        throw SkillRouterError.io("事务 \(journal.id) 无法恢复：Library 状态不明确")
    }

    private func writeJournal(_ journal: CentralTransactionJournal) throws {
        try writer.write(codec.encode(journal), to: journalURL(for: journal.id))
    }

    private func decodeJournal(_ data: Data) throws -> CentralTransactionJournal {
        var validatorData = data
        if validatorData.last == 0x0A { validatorData.removeLast() }
        let decoder = JSONDecoder()
        let journal = try decoder.decode(CentralTransactionJournal.self, from: validatorData)
        guard journal.schemaVersion == CentralTransactionJournal.currentSchemaVersion else {
            throw SkillRouterError.unsupportedSchema(document: "事务日志", version: journal.schemaVersion)
        }
        return journal
    }

    private func cleanup(_ journal: CentralTransactionJournal) throws {
        let transactionDirectory = store.paths.stagingDirectory
            .appendingPathComponent(journal.transactionDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: transactionDirectory.path) {
            try fileManager.removeItem(at: transactionDirectory)
        }
        let journalURL = journalURL(for: journal.id)
        if fileManager.fileExists(atPath: journalURL.path) {
            try fileManager.removeItem(at: journalURL)
        }
    }

    private func renameItem(_ source: URL, to destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else {
            throw SkillRouterError.io("目录切换失败：\(source.path) -> \(destination.path)，errno=\(errno)")
        }
    }

    private func journalURL(for id: UUID) -> URL {
        store.paths.journalDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func journalExists(for id: UUID) -> Bool {
        fileManager.fileExists(atPath: journalURL(for: id).path)
    }
}
