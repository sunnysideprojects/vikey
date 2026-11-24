// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ViKey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ViKey", targets: ["ViKey"]),
    ],
    targets: [
        .target(name: "ViKeyCore"),
        .executableTarget(name: "ViKey", dependencies: ["ViKeyCore"]),
        .executableTarget(name: "ViKeySelfTest", dependencies: ["ViKeyCore"]),
    ]
)
