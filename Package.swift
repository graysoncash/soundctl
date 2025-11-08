// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "soundctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "soundctl", targets: ["soundctl"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "soundctl",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
