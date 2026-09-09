// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tapr",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tapr", targets: ["Tapr"])],
    targets: [
        .target(name: "CSensor", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .target(name: "TaprCore"),
        .executableTarget(name: "Tapr", dependencies: ["TaprCore", "CSensor"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]),
        .testTarget(name: "TaprCoreTests", dependencies: ["TaprCore"])
    ]
)
