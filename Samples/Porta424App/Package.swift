// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Porta424App",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "Porta424App", targets: ["Porta424App"])
    ],
    dependencies: [
        .package(path: "../../Packages/Porta424AudioEngine")
    ],
    targets: [
        .executableTarget(
            name: "Porta424App",
            dependencies: [
                .product(name: "Porta424AudioEngine", package: "Porta424AudioEngine")
            ],
            path: "Sources/Porta424App"
        )
    ]
)
