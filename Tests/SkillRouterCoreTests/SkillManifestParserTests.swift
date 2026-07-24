import Testing
@testable import SkillRouterCore

@Suite("Skill 清单解析")
struct SkillManifestParserTests {
    @Test
    func parsesQuotedNameAndOtherMetadata() throws {
        let manifest = """
        ---
        name: "skill-router"
        description: '项目 Skill'
        note: |
          第一行
          第二行
        ---
        # 正文
        """

        let parsed = try SkillManifestParser().parse(manifest)
        #expect(parsed.name.rawValue == "skill-router")
        #expect(parsed.frontmatter["description"] == "项目 Skill")
        #expect(parsed.frontmatter["note"] == "第一行\n第二行")
    }

    @Test
    func rejectsMissingFrontmatter() {
        #expect(throws: SkillRouterError.self) {
            try SkillManifestParser().parse("# no frontmatter")
        }
    }
}
