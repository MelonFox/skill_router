// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SkillRouter",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SkillRouterCore", targets: ["SkillRouterCore"]),
        .library(name: "SkillRouterCLIKit", targets: ["SkillRouterCLIKit"]),
        .executable(name: "skill-router", targets: ["SkillRouterCLI"]),
        .executable(name: "SkillRouterApp", targets: ["SkillRouterApp"])
    ],
    targets: [
        .target(
            name: "SkillRouterCore",
            path: "Sources/SkillRouterCore",
            resources: [.copy("Resources")]
        ),
        .executableTarget(
            name: "SkillRouterCLI",
            dependencies: ["SkillRouterCore", "SkillRouterCLIKit"],
            path: "Sources/skill-router"
        ),
        .target(
            name: "SkillRouterCLIKit",
            dependencies: ["SkillRouterCore"],
            path: "Sources/SkillRouterCLIKit"
        ),
        .executableTarget(
            name: "SkillRouterApp",
            dependencies: ["SkillRouterCore"],
            path: "App/SkillRouter"
        ),
        .testTarget(
            name: "SkillRouterCoreTests",
            dependencies: ["SkillRouterCore"],
            path: "Tests/SkillRouterCoreTests"
        ),
        .testTarget(
            name: "SkillRouterFileSystemTests",
            dependencies: ["SkillRouterCore"],
            path: "Tests/SkillRouterFileSystemTests"
        ),
        .testTarget(
            name: "SkillRouterCLITests",
            dependencies: ["SkillRouterCore", "SkillRouterCLIKit"],
            path: "Tests/SkillRouterCLITests"
        )
    ]
)
