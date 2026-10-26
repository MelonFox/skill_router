import Foundation

public struct ProjectInstallResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let accepted: [String]
    public let missing: [String]
    public let reconciliation: ReconciliationReport

    public init(
        schemaVersion: Int = 1,
        accepted: [String],
        missing: [String],
        reconciliation: ReconciliationReport
    ) {
        self.schemaVersion = schemaVersion
        self.accepted = accepted.sorted()
        self.missing = missing.sorted()
        self.reconciliation = reconciliation
    }

    public var isPartial: Bool { !missing.isEmpty || reconciliation.hasFailures }
}

public final class ProjectService: @unchecked Sendable {
    private let store: RouterStateStore
    private let manifestStore: ProjectManifestStore
    private let fileManager: FileManager

    public init(
        store: RouterStateStore,
        manifestStore: ProjectManifestStore = ProjectManifestStore(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.manifestStore = manifestStore
        self.fileManager = fileManager
    }

    @discardableResult
    public func register(
        project: URL,
        targetID: String? = nil,
        target: DistributionTargetRecord? = nil,
        now: Date = Date()
    ) throws -> RegisteredProjectRecord {
        let canonical = try canonicalProject(project)
        if (targetID == nil) != (target == nil) {
            throw SkillRouterError.io("目标标识与目标配置必须同时提供")
        }

        return try store.withExclusiveState { state in
            var manifest = try manifestStore.load(from: canonical)
            if let targetID, let target {
                manifest.targets[targetID] = target
            }
            try manifestStore.save(manifest, to: canonical)

            if let existing = state.projects.first(where: { $0.path == canonical.path }) {
                return existing
            }
            let record = RegisteredProjectRecord(
                path: canonical.path,
                bookmarkData: bookmarkData(for: canonical),
                registeredAt: now
            )
            state.projects.append(record)
            return record
        }
    }

    public func unregister(project: URL) throws {
        let canonical = try canonicalProject(project)
        try store.withExclusiveState { state in
            state.projects.removeAll { $0.path == canonical.path }
        }
    }

    public func registeredProjects() throws -> [RegisteredProjectRecord] {
        try store.withExclusiveState { state in
            #if os(macOS)
            for index in state.projects.indices {
                guard let bookmarkData = state.projects[index].bookmarkData else { continue }
                var isStale = false
                guard let resolved = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL.resolvingSymlinksInPath(),
                isDirectory(resolved) else { continue }

                if resolved.path != state.projects[index].path || isStale {
                    state.projects[index] = RegisteredProjectRecord(
                        path: resolved.path,
                        bookmarkData: self.bookmarkData(for: resolved) ?? bookmarkData,
                        registeredAt: state.projects[index].registeredAt
                    )
                }
            }
            state.normalize()
            #endif
            return state.projects
        }
    }

    public func status(project: URL) throws -> ReconciliationReport {
        let canonical = try canonicalProject(project)
        let state = try store.load()
        let manifest = try manifestStore.load(from: canonical)
        return try ProjectReconciler(paths: store.paths, fileManager: fileManager)
            .reconcile(project: canonical, manifest: manifest, state: state)
    }

    public func install(
        skillNames: [SkillName],
        project: URL,
        targetID: String,
        target: DistributionTargetRecord
    ) throws -> ProjectInstallResult {
        let canonical = try canonicalProject(project)
        return try store.withExclusiveState { state in
            if !state.projects.contains(where: { $0.path == canonical.path }) {
                state.projects.append(RegisteredProjectRecord(
                    path: canonical.path,
                    bookmarkData: bookmarkData(for: canonical),
                    registeredAt: Date()
                ))
            }

            let centralNames = Set(state.skills.map(\.name))
            let acceptedNames = Array(Set(skillNames.filter { centralNames.contains($0) })).sorted()
            let missingNames = Array(Set(skillNames.filter { !centralNames.contains($0) })).sorted()
            var manifest = try manifestStore.load(from: canonical)
            manifest.targets[targetID] = target
            for name in acceptedNames {
                var targets = manifest.skills[name.rawValue]?.targets ?? []
                targets.append(targetID)
                manifest.skills[name.rawValue] = DesiredSkillAssignment(targets: targets)
            }
            try manifestStore.save(manifest, to: canonical)
            let reconciliation = try ProjectReconciler(paths: store.paths, fileManager: fileManager)
                .reconcile(project: canonical, manifest: manifest, state: state)
            return ProjectInstallResult(
                accepted: acceptedNames.map(\.rawValue),
                missing: missingNames.map(\.rawValue),
                reconciliation: reconciliation
            )
        }
    }

    public func uninstall(
        skillNames: [SkillName],
        project: URL,
        targetID: String? = nil
    ) throws -> ReconciliationReport {
        let canonical = try canonicalProject(project)
        return try store.withExclusiveState { state in
            var manifest = try manifestStore.load(from: canonical)
            for name in skillNames {
                guard var assignment = manifest.skills[name.rawValue] else { continue }
                if let targetID {
                    assignment.targets.removeAll { $0 == targetID }
                    if assignment.targets.isEmpty {
                        manifest.skills.removeValue(forKey: name.rawValue)
                    } else {
                        manifest.skills[name.rawValue] = DesiredSkillAssignment(targets: assignment.targets)
                    }
                } else {
                    manifest.skills.removeValue(forKey: name.rawValue)
                }
            }
            try manifestStore.save(manifest, to: canonical)
            return try ProjectReconciler(paths: store.paths, fileManager: fileManager)
                .reconcile(project: canonical, manifest: manifest, state: state)
        }
    }

    public func uninstallAll(project: URL) throws -> ReconciliationReport {
        let canonical = try canonicalProject(project)
        return try store.withExclusiveState { state in
            var manifest = try manifestStore.load(from: canonical)
            manifest.skills = [:]
            try manifestStore.save(manifest, to: canonical)
            return try ProjectReconciler(paths: store.paths, fileManager: fileManager)
                .reconcile(project: canonical, manifest: manifest, state: state)
        }
    }

    public func reconcile(project: URL) throws -> ReconciliationReport {
        try status(project: project)
    }

    public func gitIgnoreEntries(project: URL) throws -> [String] {
        let canonical = try canonicalProject(project)
        let manifest = try manifestStore.load(from: canonical)
        var entries = Set<String>()
        for (skillName, assignment) in manifest.skills {
            for targetID in assignment.targets {
                guard let target = manifest.targets[targetID] else { continue }
                entries.insert("/\(target.path)/\(skillName)")
            }
        }
        return entries.sorted()
    }

    @discardableResult
    public func addGitIgnoreEntries(project: URL) throws -> [String] {
        let canonical = try canonicalProject(project)
        let entries = try gitIgnoreEntries(project: canonical)
        guard !entries.isEmpty else { return [] }

        let gitIgnore = canonical.appendingPathComponent(".gitignore")
        let current = (try? String(contentsOf: gitIgnore, encoding: .utf8)) ?? ""
        let currentLines = Set(current.split(whereSeparator: \.isNewline).map(String.init))
        let missing = entries.filter { !currentLines.contains($0) }
        guard !missing.isEmpty else { return [] }

        var updated = current
        if !updated.isEmpty, !updated.hasSuffix("\n") { updated += "\n" }
        if !updated.isEmpty { updated += "\n" }
        updated += "# Skill Router 管理的软链接\n"
        updated += missing.joined(separator: "\n") + "\n"
        try AtomicFileWriter().write(Data(updated.utf8), to: gitIgnore)
        return missing
    }

    private func bookmarkData(for url: URL) -> Data? {
        #if os(macOS)
        return try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return nil
        #endif
    }

    private func canonicalProject(_ project: URL) throws -> URL {
        let canonical = project.standardizedFileURL.resolvingSymlinksInPath()
        guard isDirectory(canonical) else {
            throw SkillRouterError.io("项目目录不存在：\(canonical.path)")
        }
        return canonical
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
