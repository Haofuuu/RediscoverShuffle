// swift-tools-version: 6.0
import PackageDescription

// This small companion manifest lets the Apple-independent shuffle tests run
// on Macs where the full iOS SDK is not installed. The iPhone app itself is
// built from RediscoverShuffle.xcodeproj.
let package = Package(
    name: "RediscoverShuffleCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RediscoverShuffleCore", targets: ["RediscoverShuffleCore"])
    ],
    targets: [
        .target(
            name: "RediscoverShuffleCore",
            path: "RediscoverShuffle/Shuffle"
        ),
        .testTarget(
            name: "RediscoverShuffleCoreTests",
            dependencies: ["RediscoverShuffleCore"],
            path: "RediscoverShuffleCoreTests"
        )
    ]
)
