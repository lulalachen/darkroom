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
            path: "Sources",
            resources: [
                .copy("Resources/AppIcon.icon"),
                .copy("Resources/AppIcon.png"),
                .copy("Resources/LUT")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "darkroomTests",
            dependencies: ["darkroom"],
            path: "Tests"
        ),
        .plugin(
            name: "BundleAppPlugin",
            capability: .command(
                intent: .custom(
                    verb: "bundle-app",
                    description: "Build and bundle Darkroom.app"
                ),
                permissions: [
                    .writeToPackageDirectory(
                        reason: "Creates dist/<configuration>/Darkroom.app output."
                    )
                ]
            )
        )
    ]
)
