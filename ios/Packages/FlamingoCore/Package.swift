// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlamingoCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "FlamingoCore", targets: ["FlamingoCore"])],
    targets: [
        .target(name: "FlamingoCore"),
        .testTarget(name: "FlamingoCoreTests", dependencies: ["FlamingoCore"])
    ]
)
