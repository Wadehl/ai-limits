// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AiLimits",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AiLimitsCore", targets: ["AiLimitsCore"]),
        .library(name: "AiLimitsUI", targets: ["AiLimitsUI"]),
        .executable(name: "AiLimitsApp", targets: ["AiLimitsApp"]),
        .executable(name: "AiLimitsWidget", targets: ["AiLimitsWidget"]),
        .executable(name: "AiLimitsWidgetPreview", targets: ["AiLimitsWidgetPreview"])
    ],
    targets: [
        .target(name: "AiLimitsCore"),
        .target(name: "AiLimitsUI", dependencies: ["AiLimitsCore"]),
        .executableTarget(name: "AiLimitsApp", dependencies: ["AiLimitsCore", "AiLimitsUI"]),
        .executableTarget(name: "AiLimitsWidget", dependencies: ["AiLimitsCore", "AiLimitsUI"]),
        .executableTarget(name: "AiLimitsWidgetPreview", dependencies: ["AiLimitsCore", "AiLimitsUI"]),
        .testTarget(name: "AiLimitsUITests", dependencies: ["AiLimitsUI", "AiLimitsCore"]),
        .testTarget(name: "AiLimitsCoreTests", dependencies: ["AiLimitsCore"])
    ]
)
