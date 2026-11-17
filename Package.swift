// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TSAIUsageBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TSAIUsageBar", targets: ["TSAIUsageBar"]),
        .executable(name: "tsai-usagebar-hook", targets: ["tsai-usagebar-hook"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "TSAIUsageBar", dependencies: ["UsageCore"]),
        .executableTarget(name: "tsai-usagebar-hook", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
