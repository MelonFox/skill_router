import Foundation
import Testing
@testable import SkillRouterCore

@Suite("JSON v1 契约")
struct JSONContractTests {
    private let codec = VersionedJSONCodec()

    @Test
    func routerStateRoundTripsDeterministically() throws {
        let later = try SkillName(rawValue: "z-skill")
        let earlier = try SkillName(rawValue: "a-skill")
        let state = RouterState(skills: [
            ManagedSkillRecord(name: later, origin: .local, suiteName: nil, sourceID: nil, contentRelativePath: "Library/Skills/z-skill", importedAt: Date(timeIntervalSince1970: 2)),
            ManagedSkillRecord(name: earlier, origin: .local, suiteName: nil, sourceID: nil, contentRelativePath: "Library/Skills/a-skill", importedAt: Date(timeIntervalSince1970: 1))
        ])

        let first = try codec.encode(state)
        let decoded = try codec.decodeRouterState(first)
        let second = try codec.encode(decoded)
        #expect(first == second)
        #expect(decoded.skills.map(\.name) == [earlier, later])
    }

    @Test
    func projectManifestRoundTripsMultipleTargets() throws {
        let manifest = ProjectManifest(
            targets: ["codex": .codex, "claude-code": .claudeCode],
            skills: ["skill-router": DesiredSkillAssignment(targets: ["codex", "claude-code", "codex"])]
        )
        let data = try codec.encode(manifest)
        let decoded = try codec.decodeProjectManifest(data)
        #expect(decoded == ProjectManifest(
            targets: ["codex": .codex, "claude-code": .claudeCode],
            skills: ["skill-router": DesiredSkillAssignment(targets: ["claude-code", "codex"])]
        ))
    }

    @Test
    func rejectsUnknownSchema() throws {
        let data = Data("{\"schemaVersion\":99,\"skills\":{},\"targets\":{}}".utf8)
        #expect(throws: SkillRouterError.unsupportedSchema(document: ".skill-router.json", version: 99)) {
            try codec.decodeProjectManifest(data)
        }
    }

    @Test
    func rejectsDuplicateFields() {
        let data = Data("{\"schemaVersion\":1,\"schemaVersion\":1,\"skills\":{},\"targets\":{}}".utf8)
        #expect(throws: SkillRouterError.self) {
            try codec.decodeProjectManifest(data)
        }
    }

    @Test
    func rejectsMissingTargetReference() throws {
        let manifest = ProjectManifest(skills: ["skill-router": DesiredSkillAssignment(targets: ["codex"])])
        let data = try codec.encode(manifest)
        #expect(throws: SkillRouterError.self) {
            try codec.decodeProjectManifest(data)
        }
    }
}
