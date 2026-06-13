// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "soundctl",
    platforms: [.macOS(.v14)],
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
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist so the Bluetooth usage description ships in
                // the binary (required for the permission prompt).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/soundctl/Info.plist",
                ])
            ]
        )
    ]
)
