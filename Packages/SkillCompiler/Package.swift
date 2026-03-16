// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SkillCompiler",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SkillCompiler",
            targets: ["SkillCompiler"]
        ),
    ],
    dependencies: [
        .package(path: "../RouterCore"),
        .package(path: "../SkillRegistry"),
    ],
    targets: [
        .target(
            name: "SkillCompiler",
            dependencies: [
                "RouterCore",
                "SkillRegistry",
            ]
        ),
        .testTarget(
            name: "SkillCompilerTests",
            dependencies: ["SkillCompiler"]
        ),
    ]
)
