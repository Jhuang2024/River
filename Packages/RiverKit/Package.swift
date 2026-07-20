// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RiverKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "RiverKit", targets: ["RiverKit"])
    ],
    targets: [
        .target(name: "RiverKit"),
        .testTarget(name: "RiverKitTests", dependencies: ["RiverKit"])
    ]
)
