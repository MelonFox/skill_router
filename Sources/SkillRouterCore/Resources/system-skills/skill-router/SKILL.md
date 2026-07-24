---
name: skill-router
description: 在当前项目中注册项目，并按用户要求安装中央库中已有的一个或多个 Skill。
---

# Skill Router 项目请求

当用户要求为当前项目安装 Skill 时：

1. 使用固定路径 `~/.skill-router/bin/skill-router`。
2. 判断当前 Agent：Codex 使用 `--target codex`，Claude Code 使用 `--target claude-code`。
3. 若当前项目尚未注册，执行 `project register --target <当前目标>`。
4. 执行 `project install <skill>... --target <当前目标>` 安装用户明确指定的 Skill。
5. 如命令返回部分完成或失败，原样向用户说明缺失名称、目标冲突和真实退出码。

本 Skill 不卸载项目 Skill，不导入或删除中央 Skill，也不直接编辑 `.skill-router.json`。
