// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "darkroom",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DarkroomApp",
            targets: ["darkroom"]
        )
    ],
    targets: [
        .executableTarget(
            name: "darkroom",
            path: "Sources"
        ),
    ]
)
