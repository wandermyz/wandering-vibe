// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PracticePiano",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PracticePiano", targets: ["PracticePiano"])],
    targets: [
        .target(name: "PianoCore"),
        .executableTarget(name: "PracticePiano", dependencies: ["PianoCore"]),
        .testTarget(name: "PianoCoreTests", dependencies: ["PianoCore"])
    ]
)
