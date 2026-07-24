import Testing
@testable import SkillRouterCore

@Suite("Skill 名称")
struct SkillNameTests {
    @Test(arguments: ["a", "skill-router", "abc123", String(repeating: "a", count: 64)])
    func acceptsValidNames(_ raw: String) throws {
        #expect(try SkillName(rawValue: raw).rawValue == raw)
    }

    @Test(arguments: ["", "Skill", "-skill", "skill-", "skill--router", "skill_router", "技能", String(repeating: "a", count: 65)])
    func rejectsInvalidNames(_ raw: String) {
        #expect(throws: SkillRouterError.self) {
            try SkillName(rawValue: raw)
        }
    }
}
