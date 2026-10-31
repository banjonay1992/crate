// swift-tools-version:6.0
import PackageDescription

// CrateCore holds everything in Crate that does not need UIKit, SwiftUI or
// AVFoundation: the Discogs client, models, identifier matching, the offline
// cache and lookup queue, and the dig log. It has no third-party dependencies
// and builds on macOS, iOS and Linux so it can be tested anywhere.
let package = Package(
    name: "CrateCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CrateCore", targets: ["CrateCore"]),
    ],
    targets: [
        .target(
            name: "CrateCore",
            path: "Sources/CrateCore"
        ),
        .testTarget(
            name: "CrateCoreTests",
            dependencies: ["CrateCore"],
            path: "Tests/CrateCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
