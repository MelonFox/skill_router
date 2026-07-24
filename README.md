# Skill Router

Skill Router 是一个原生 macOS 本地应用，用一份中央 Skill 内容按需服务多个项目。项目只保存期望清单和指向中央库的软链接；本地导入、公开 Git 来源、项目分发、确认更新和 `.skillrouter` 制品都由同一核心库处理。

## 当前范围

- 支持 macOS 15 及以上、Apple Silicon。
- 支持本地单 Skill、本地多 Skill 套件和公开 Git URL 导入。
- 支持 Codex、Claude Code 和自定义项目相对目标。
- 支持界面主动分发，也支持全局 `skill-router` 系统 Skill 通过正式 CLI 从当前项目请求安装。
- 支持确认后更新中央库、中央删除、项目协调和套件重命名。
- 支持选择或全部导出 `.skillrouter`，由用户自行同步制品。
- 不支持分类分组、应用内创建编辑、私有 Git、分享市场、云同步、版本回滚或应用内升级。

## 本地运行

前置条件：Xcode 已安装、许可协议已接受，并已选择可用的命令行工具。

在仓库根目录执行：

```zsh
./scripts/run-local.sh
```

脚本会先构建 `skill-router` CLI，再启动 SwiftUI 应用。应用首次启动会创建 `~/.skill-router/`，安装 CLI 和内置系统 Skill，并尝试建立：

```text
~/.agents/skills/skill-router
~/.claude/skills/skill-router
```

如目标位置已有不受管同名文件、目录或软链接，应用会报告冲突，不会覆盖。

## 自动测试

```zsh
swift test
xcodebuild build -scheme SkillRouterApp -destination 'platform=macOS,arch=arm64'
xcodebuild test -scheme SkillRouter-Package -destination 'platform=macOS,arch=arm64'
```

测试使用独立临时目录，不应修改真实 `~/.skill-router` 或真实项目。测试只验证目录、清单和软链接结构，不启动 Codex 或 Claude Code，不证明 Agent 已真实发现、加载或执行 Skill。

## CLI

应用首次初始化后，固定 CLI 位于：

```text
~/.skill-router/bin/skill-router
```

查看帮助：

```zsh
~/.skill-router/bin/skill-router help
```

CLI 覆盖项目注册、列表、状态、安装、卸载和协调，支持中文文本和 `--json` 版本化输出。自定义目标必须先由界面写入项目清单，再通过其目标标识调用。

## 文档

- [首版产品规格](docs/product-spec.md)
- [实施计划与结果](docs/implementation-plan.md)
- [本地人工验收清单](docs/local-acceptance-checklist.md)
- [领域语言](CONTEXT.md)

当前目录尚未初始化 Git，项目也未执行签名、公证或 GitHub Release。对外下载发布属于后续阶段，需要单独确定 Bundle Identifier、Developer ID 团队和仓库地址。
