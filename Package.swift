// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacWheel",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MacWheelCore", targets: ["MacWheelCore"]),
        .executable(name: "MacWheel", targets: ["MacWheel"]),
        .executable(name: "MacWheelTestsRunner", targets: ["MacWheelTestsRunner"])
    ],
    targets: [
        .target(
            name: "MacWheelCore",
            path: "Sources/MacWheelCore"
        ),
        .executableTarget(
            name: "MacWheel",
            dependencies: ["MacWheelCore"],
            path: "Sources/MacWheel"
        ),
        .executableTarget(
            name: "MacWheelTestsRunner",
            dependencies: ["MacWheelCore"],
            path: "Sources/MacWheelTestsRunner"
        )
    ]
)
