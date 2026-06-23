// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BizneoCompanion",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "BizneoCore"
        ),
        .executableTarget(
            name: "BizneoCompanion",
            dependencies: ["BizneoCore"]
        ),
        .testTarget(
            name: "BizneoCompanionTests",
            dependencies: ["BizneoCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
