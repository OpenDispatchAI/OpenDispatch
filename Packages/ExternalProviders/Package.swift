// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ExternalProviders",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ExternalProviders",
            targets: ["ExternalProviders"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilityRegistry"),
        .package(path: "../Executors"),
        .package(path: "../RouterCore"),
        .package(path: "../SkillRegistry"),
    ],
    targets: [
        .target(
            name: "ExternalProviders",
            dependencies: [
                "CapabilityRegistry",
                "Executors",
                "RouterCore",
                "SkillRegistry",
            ]
        ),
        .testTarget(
            name: "ExternalProvidersTests",
            dependencies: ["ExternalProviders"]
        ),
    ]
)
