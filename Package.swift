// swift-tools-version:5.9
// Builds and tests the app's platform-independent core (PixelDeck/Core) with `swift test`.
// The app itself is built from PixelDeck.xcodeproj.
import PackageDescription

let package = Package(
    name: "PixelDeckCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    targets: [
        .target(name: "PixelDeckCore", path: "PixelDeck/Core"),
        .testTarget(name: "PixelDeckCoreTests", dependencies: ["PixelDeckCore"], path: "Tests/PixelDeckCoreTests"),
    ]
)
