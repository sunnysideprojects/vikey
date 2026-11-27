// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ViKey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ViKey", targets: ["ViKey"]),
    ],
    dependencies: [
        // In-app updates (MIT). build.sh embeds Sparkle.framework in Contents/Frameworks.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "ViKeyCore"),
        .executableTarget(
            name: "ViKey",
            dependencies: ["ViKeyCore", .product(name: "Sparkle", package: "Sparkle")],
            // Find Sparkle.framework in the app bundle, and next to the binary for `swift run`.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                                           "-Xlinker", "-rpath", "-Xlinker", "@loader_path"])]
        ),
        .executableTarget(name: "ViKeySelfTest", dependencies: ["ViKeyCore"]),
    ]
)
