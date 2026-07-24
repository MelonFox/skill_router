# CLI 固定安装在 `~/.skill-router/bin`

Skill Router 将配套 CLI 安装为 `~/.skill-router/bin/skill-router`，项目请求 Skill 使用该绝对路径调用，不依赖用户 `PATH`，也不写入 `/usr/local/bin` 或请求管理员权限；原生应用升级时同步刷新这份 CLI。相比引用 `.app` 内部路径或修改系统级命令目录，这能在应用未运行时提供稳定入口；代价是用户若想直接键入短命令，需要自行把目录加入 `PATH`。
