// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Porta424AudioEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Porta424AudioEngine", targets: ["Porta424AudioEngine"])
    ],
    dependencies: [
        .package(path: "../PortaDSPKit")
    ],
    targets: [
        .target(
            name: "Porta424AudioEngine",
            dependencies: [
                .product(name: "PortaDSPKit", package: "PortaDSPKit")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "Porta424AudioEngineTests",
            dependencies: ["Porta424AudioEngine"]
        )
    ]
)
