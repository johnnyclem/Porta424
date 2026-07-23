
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortaDSPKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PortaDSPKit", targets: ["PortaDSPKit"]),
    ],
    targets: [
        // C/C++ bridge target exposing C-API for Swift
        .target(
            name: "PortaDSPBridge",
            path: "Sources/PortaDSPBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                // DSP headers are pulled via relative #includes in portadsp_bridge.cpp
                // (../../../../DSPCore/...). SPM forbids headerSearchPath outside the package root.
                .define("PORTA_DSP_BRIDGE")
            ],
            linkerSettings: [
                .linkedLibrary("atomic", .when(platforms: [.linux]))
            ]
        ),
        // Swift façade target that UI engineers import
        .target(
            name: "PortaDSPKit",
            dependencies: ["PortaDSPBridge"],
            path: "Sources/PortaDSPKit"
        ),
        .testTarget(
            name: "PortaDSPKitTests",
            dependencies: ["PortaDSPKit"],
            path: "Tests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
