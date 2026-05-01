// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DouziMenuBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DouziMenuBar", targets: ["DouziMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "DouziMenuBar",
            resources: [.copy("Resources")]
        )
    ]
)
