// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lodestar",
    platforms: [.macOS(.v14)],   // ScreenCaptureKit SCScreenshotManager
    products: [
        .executable(name: "Lodestar", targets: ["Lodestar"]),
    ],
    targets: [
        // Zero external dependencies — pure system frameworks, so it builds offline
        // and stays a small, auditable binary. That is a deliberate design goal.
        .executableTarget(
            name: "Lodestar",
            path: "Sources/Lodestar"
        ),
        .testTarget(
            name: "LodestarTests",
            dependencies: ["Lodestar"],
            path: "Tests/LodestarTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
