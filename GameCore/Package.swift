// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GameCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "GameCore", targets: ["GameCore"]),
        .executable(name: "BalanceLab", targets: ["BalanceLab"]),
    ],
    targets: [
        .target(name: "GameCore"),
        .executableTarget(name: "BalanceLab", dependencies: ["GameCore"]),
        .testTarget(name: "GameCoreTests", dependencies: ["GameCore"]),
    ]
)
