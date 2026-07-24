# 先本地运行，后通过 GitHub 直接发布

开发阶段优先保证 Skill Router 在本机直接构建和运行，不为首个可用版本引入 Mac App Store、安装器或发布自动化；面向用户发布时通过 GitHub Releases 提供 Developer ID 签名并完成 Apple 公证的非沙盒应用与配套 CLI。首版不在应用内检查或安装自身更新，用户手动下载并替换新版。相比从一开始适配 App Sandbox，这最符合任意项目目录、全局 Agent 目录和命令行工作流的权限模型；代价是团队需要自行维护签名、公证和 GitHub 发布流程，且不获得 App Store 分发或应用内升级能力。
