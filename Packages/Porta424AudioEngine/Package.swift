// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Porta424AudioEngine",
    platforms: [
        .iOS(.v15), .macOS(.v12)
    ],
    products: [
        .library(name: "Porta424AudioEngine", targets: ["Porta424AudioEngine"])
    ],
    targets: [
        .target(
            name: "Porta424AudioEngine",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "Porta424AudioEngineTests",
            dependencies: ["Porta424AudioEngine"]
        )
    ]
)
