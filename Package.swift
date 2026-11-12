// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBlueprint",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BlueprintCore", targets: ["BlueprintCore"]),
    ],
    targets: [
        .target(name: "BlueprintCore"),
        .testTarget(name: "BlueprintCoreTests", dependencies: ["BlueprintCore"]),
    ]
)
