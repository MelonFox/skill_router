# 项目请求 Skill 作为应用内置系统 Skill

名为 `skill-router` 的项目请求 Skill 随 Skill Router 安装和升级。首次启动时，应用自动创建中央根目录、安装配套 CLI，并在 Codex 与 Claude Code 的全局 Skill 目录中都启用该系统 Skill，不先请求逐目标确认；之后用户可以从设置停用或修复。系统 Skill 在界面中与普通托管 Skill 分开呈现，用户不能编辑或删除其内容。相比把它作为普通 Skill 或交给用户手工安装，这能保证项目侧入口开箱可用且与配套 CLI 兼容；代价是首次启动会主动修改两个 Agent 的全局 Skill 目录，应用也需要维护这些安装状态和系统 Skill 的独立生命周期。
