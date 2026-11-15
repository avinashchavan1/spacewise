// swift-tools-version:5.9
// Builds and tests the scanning engine on its own (`swift test`).
// The app itself is built from Spacewise.xcodeproj.
import PackageDescription

let package = Package(
    name: "SpacewiseCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SpacewiseCore", path: "Spacewise/Core"),
        .testTarget(name: "SpacewiseCoreTests", dependencies: ["SpacewiseCore"], path: "Tests/SpacewiseCoreTests"),
    ]
)
