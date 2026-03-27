// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Porta424App",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Porta424App", targets: ["Porta424App"])
    ],
    dependencies: [
        .package(path: "../Packages/PortaDSPKit"),
        .package(path: "../Packages/Porta424AudioEngine")
    ],
    targets: [
        .executableTarget(
            name: "Porta424App",
            dependencies: [
                .product(name: "PortaDSPKit", package: "PortaDSPKit"),
                .product(name: "Porta424AudioEngine", package: "Porta424AudioEngine")
            ],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
