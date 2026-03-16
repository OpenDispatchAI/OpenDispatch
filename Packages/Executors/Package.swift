// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Executors",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Executors",
            targets: ["Executors"]
        ),
    ],
    dependencies: [
        .package(path: "../RouterCore"),
    ],
    targets: [
        .target(
            name: "Executors",
            dependencies: ["RouterCore"]
        ),
        .testTarget(
            name: "ExecutorsTests",
            dependencies: ["Executors"]
        ),
    ]
)
