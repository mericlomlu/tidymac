// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TidyMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TidyMac", targets: ["TidyMac"]),
        .library(name: "TidyCore", targets: ["TidyCore"]),
    ],
    targets: [
        .target(name: "TidyCore"),
        .executableTarget(name: "TidyMac", dependencies: ["TidyCore"]),
        .testTarget(name: "TidyCoreTests", dependencies: ["TidyCore"]),
    ]
)
