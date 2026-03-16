// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CapabilityRegistry",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CapabilityRegistry",
            targets: ["CapabilityRegistry"]
        ),
    ],
    targets: [
        .target(
            name: "CapabilityRegistry"
        ),
        .testTarget(
            name: "CapabilityRegistryTests",
            dependencies: ["CapabilityRegistry"]
        ),
    ]
)
