// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProjectBoard",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.executable(name: "ProjectBoard", targets: ["ProjectBoard"])],
    targets: [
        .target(name: "BoardCore"),
        .executableTarget(name: "ProjectBoard", dependencies: ["BoardCore"]),
        .testTarget(name: "BoardCoreTests", dependencies: ["BoardCore"])
    ]
)
