// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBlueprint",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BlueprintCore", targets: ["BlueprintCore"]),
        .executable(name: "macblueprint", targets: ["macblueprint"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BlueprintCore"),
        .executableTarget(
            name: "macblueprint",
            dependencies: [
                "BlueprintCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "BlueprintCoreTests", dependencies: ["BlueprintCore"]),
    ]
)
