import Foundation

public struct ProjectManifestStore: Sendable {
    public static let fileName = ".skill-router.json"

    private let codec: VersionedJSONCodec
    private let writer: AtomicFileWriter

    public init(
        codec: VersionedJSONCodec = VersionedJSONCodec(),
        writer: AtomicFileWriter = AtomicFileWriter()
    ) {
        self.codec = codec
        self.writer = writer
    }

    public func manifestURL(forProject project: URL) -> URL {
        project.appendingPathComponent(Self.fileName)
    }

    public func load(from project: URL) throws -> ProjectManifest {
        let url = manifestURL(forProject: project)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectManifest()
        }
        do {
            return try codec.decodeProjectManifest(Data(contentsOf: url))
        } catch let error as SkillRouterError {
            throw error
        } catch {
            throw SkillRouterError.io(error.localizedDescription)
        }
    }

    public func save(_ manifest: ProjectManifest, to project: URL) throws {
        var normalized = manifest
        normalized.normalize()
        try normalized.validate()
        try writer.write(codec.encode(normalized), to: manifestURL(forProject: project))
    }
}
