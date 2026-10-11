// swift-tools-version:5.10
import PackageDescription

// Models, catalogue logic, online lookup, Claude client, texts and the on-device store.
// No UI code here, so `swift test` runs on a plain Mac (or macOS runner).
let package = Package(
    name: "MybibCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MybibCore", targets: ["MybibCore"]),
    ],
    targets: [
        .target(name: "MybibCore", path: "Sources/MybibCore"),
        .testTarget(name: "MybibCoreTests", dependencies: ["MybibCore"], path: "Tests/MybibCoreTests"),
    ],
    swiftLanguageVersions: [.v5]
)
