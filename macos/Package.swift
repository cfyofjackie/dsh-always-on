// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DSHAlwaysOn",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CompanionCore", targets: ["CompanionCore"]),
        .executable(name: "DSHAlwaysOn", targets: ["DSHAlwaysOn"])
    ],
    targets: [
        .target(name: "CompanionCore"),
        .executableTarget(name: "DSHAlwaysOn", dependencies: ["CompanionCore"]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"])
    ],
    swiftLanguageModes: [.v5]
)
