// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RouterCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RouterCore",
            targets: ["RouterCore"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilityRegistry"),
    ],
    targets: [
        .target(
            name: "RouterCore",
            dependencies: [
                "CapabilityRegistry",
            ]
        ),
        .testTarget(
            name: "RouterCoreTests",
            dependencies: ["RouterCore", "CapabilityRegistry"]
        ),
    ]
)
