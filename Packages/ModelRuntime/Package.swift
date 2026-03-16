// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ModelRuntime",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "ModelRuntime",
            targets: ["ModelRuntime"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilityRegistry"),
        .package(path: "../RouterCore"),
    ],
    targets: [
        .target(
            name: "ModelRuntime",
            dependencies: [
                "CapabilityRegistry",
                "RouterCore",
            ]
        ),
        .testTarget(
            name: "ModelRuntimeTests",
            dependencies: ["ModelRuntime"]
        ),
    ]
)
