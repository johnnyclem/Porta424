// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortaDSPKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PortaDSPKit",
            targets: ["PortaDSPKit"]
        )
    ],
    targets: [
        .target(
            name: "PortaDSPBridge",
            path: "Packages/PortaDSPKit/Sources/PortaDSPBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("PORTA_DSP_BRIDGE"),
                .headerSearchPath("../../../../DSPCore"),
                .headerSearchPath("../../../../DSPCore/include")
            ],
            linkerSettings: [
                .linkedLibrary("atomic", .when(platforms: [.linux]))
            ]
        ),
        .target(
            name: "PortaDSPKit",
            dependencies: ["PortaDSPBridge"],
            path: "Packages/PortaDSPKit/Sources/PortaDSPKit"
        ),
        .testTarget(
            name: "PortaDSPKitTests",
            dependencies: ["PortaDSPKit"],
            path: "Packages/PortaDSPKit/Tests"
        ),
        .testTarget(
            name: "PortaDSPPerformanceTests",
            dependencies: ["PortaDSPKit"],
            path: "Packages/PortaDSPKit/PerformanceTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
