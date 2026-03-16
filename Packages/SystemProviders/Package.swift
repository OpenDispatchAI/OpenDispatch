// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SystemProviders",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SystemProviders",
            targets: ["SystemProviders"]
        ),
    ],
    dependencies: [
        .package(path: "../CapabilityRegistry"),
        .package(path: "../Executors"),
        .package(path: "../RouterCore"),
    ],
    targets: [
        .target(
            name: "SystemProviders",
            dependencies: [
                "CapabilityRegistry",
                "Executors",
                "RouterCore",
            ]
        ),
        .testTarget(
            name: "SystemProvidersTests",
            dependencies: ["SystemProviders"]
        ),
    ]
)
