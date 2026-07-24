# 首版仅支持 macOS 15 与 Apple Silicon

Skill Router 首版最低系统为 macOS 15，只构建和验证 Apple Silicon `arm64`，与当前 macOS 15.7.3 开发机和 Swift 6.1.2 环境一致。相比同时支持 Intel 或更老系统，这能使用当前 SwiftUI 能力并保持真实测试矩阵最窄；代价是 Intel Mac 和 macOS 14 及更早版本用户无法运行首版，未来扩展支持时需要单独补充构建与验证。
