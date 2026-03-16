// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SkillRegistry",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SkillRegistry",
            targets: ["SkillRegistry"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilityRegistry"),
        .package(path: "../RouterCore"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "SkillRegistry",
            dependencies: [
                "CapabilityRegistry",
                "RouterCore",
                "Yams",
            ]
        ),
        .testTarget(
            name: "SkillRegistryTests",
            dependencies: ["SkillRegistry"]
        ),
    ]
)
